// The destination package handles uploading to a specific destination (delegates
// to filestore or objectstore packages) based on options from the pre-authorization
// API and finalizing the upload.
package destination

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v4"

	"gitlab.com/gitlab-org/labkit/log"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/secret"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/upload/destination/filestore"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/upload/destination/objectstore"
)

type SizeError error

// ErrEntityTooLarge means that the uploaded content is bigger then maximum allowed size
var ErrEntityTooLarge = errors.New("entity is too large")

// FileHandler represent a file that has been processed for upload
// it may be either uploaded to an ObjectStore and/or saved on local path.
type FileHandler struct {
	// LocalPath is the path on the disk where file has been stored
	LocalPath string

	// RemoteID is the objectID provided by GitLab Rails
	RemoteID string
	// RemoteURL is ObjectStore URL provided by GitLab Rails
	RemoteURL string

	// Size is the persisted file size
	Size int64

	// Name is the resource name to send back to GitLab rails.
	// It differ from the real file name in order to avoid file collisions
	Name string

	// a map containing different hashes
	hashes map[string]string

	// Duration of upload in seconds
	uploadDuration float64
}

type uploadClaims struct {
	Upload map[string]string `json:"upload"`
	jwt.StandardClaims
}

// SHA256 hash of the handled file
func (fh *FileHandler) SHA256() string {
	return fh.hashes["sha256"]
}

// MD5 hash of the handled file
func (fh *FileHandler) MD5() string {
	return fh.hashes["md5"]
}

// GitLabFinalizeFields returns a map with all the fields GitLab Rails needs in order to finalize the upload.
func (fh *FileHandler) GitLabFinalizeFields(prefix string) (map[string]string, error) {
	// TODO: remove `data` these once rails fully and exclusively support `signedData` (https://gitlab.com/gitlab-org/gitlab/-/issues/324873)
	data := make(map[string]string)
	signedData := make(map[string]string)
	key := func(field string) string {
		if prefix == "" {
			return field
		}

		return fmt.Sprintf("%s.%s", prefix, field)
	}

	for k, v := range map[string]string{
		"name":            fh.Name,
		"path":            fh.LocalPath,
		"remote_url":      fh.RemoteURL,
		"remote_id":       fh.RemoteID,
		"size":            strconv.FormatInt(fh.Size, 10),
		"upload_duration": strconv.FormatFloat(fh.uploadDuration, 'f', -1, 64),
	} {
		data[key(k)] = v
		signedData[k] = v
	}

	for hashName, hash := range fh.hashes {
		data[key(hashName)] = hash
		signedData[hashName] = hash
	}

	claims := uploadClaims{Upload: signedData, StandardClaims: secret.DefaultClaims}
	jwtData, err := secret.JWTTokenString(claims)
	if err != nil {
		return nil, err
	}
	data[key("gitlab-workhorse-upload")] = jwtData

	return data, nil
}

type consumer interface {
	Consume(context.Context, io.Reader, time.Time) (int64, error)
}

// Upload persists the provided reader content to all the location specified in opts. A cleanup will be performed once ctx is Done
// Make sure the provided context will not expire before finalizing upload with GitLab Rails.
func Upload(ctx context.Context, reader io.Reader, size int64, opts *UploadOpts) (*FileHandler, error) {
	fh := &FileHandler{
		Name:      opts.TempFilePrefix,
		RemoteID:  opts.RemoteID,
		RemoteURL: opts.RemoteURL,
	}
	uploadStartTime := time.Now()
	defer func() { fh.uploadDuration = time.Since(uploadStartTime).Seconds() }()
	hashes := newMultiHash()
	reader = io.TeeReader(reader, hashes.Writer)

	var clientMode string
	var uploadDestination consumer
	var err error
	switch {
	case opts.IsLocal():
		clientMode = "local"
		uploadDestination, err = fh.newLocalFile(ctx, opts)
	case opts.UseWorkhorseClientEnabled() && opts.ObjectStorageConfig.IsGoCloud():
		clientMode = fmt.Sprintf("go_cloud:%s", opts.ObjectStorageConfig.Provider)
		p := &objectstore.GoCloudObjectParams{
			Ctx:        ctx,
			Mux:        opts.ObjectStorageConfig.URLMux,
			BucketURL:  opts.ObjectStorageConfig.GoCloudConfig.URL,
			ObjectName: opts.RemoteTempObjectID,
		}
		uploadDestination, err = objectstore.NewGoCloudObject(p)
	case opts.UseWorkhorseClientEnabled() && opts.ObjectStorageConfig.IsAWS() && opts.ObjectStorageConfig.IsValid():
		clientMode = "s3"
		uploadDestination, err = objectstore.NewS3Object(
			opts.RemoteTempObjectID,
			opts.ObjectStorageConfig.S3Credentials,
			opts.ObjectStorageConfig.S3Config,
		)
	case opts.IsMultipart():
		clientMode = "multipart"
		uploadDestination, err = objectstore.NewMultipart(
			opts.PresignedParts,
			opts.PresignedCompleteMultipart,
			opts.PresignedAbortMultipart,
			opts.PresignedDelete,
			opts.PutHeaders,
			opts.PartSize,
		)
	default:
		clientMode = "http"
		uploadDestination, err = objectstore.NewObject(
			opts.PresignedPut,
			opts.PresignedDelete,
			opts.PutHeaders,
			size,
		)
	}

	if err != nil {
		return nil, err
	}

	var hlr *hardLimitReader
	if opts.MaximumSize > 0 {
		if size > opts.MaximumSize {
			return nil, SizeError(fmt.Errorf("the upload size %d is over maximum of %d bytes", size, opts.MaximumSize))
		}

		hlr = &hardLimitReader{r: reader, n: opts.MaximumSize}
		reader = hlr
	}

	fh.Size, err = uploadDestination.Consume(ctx, reader, opts.Deadline)
	if err != nil {
		if (err == objectstore.ErrNotEnoughParts) || (hlr != nil && hlr.n < 0) {
			err = ErrEntityTooLarge
		}
		return nil, err
	}

	if size != -1 && size != fh.Size {
		return nil, SizeError(fmt.Errorf("expected %d bytes but got only %d", size, fh.Size))
	}

	logger := log.WithContextFields(ctx, log.Fields{
		"copied_bytes":     fh.Size,
		"is_local":         opts.IsLocal(),
		"is_multipart":     opts.IsMultipart(),
		"is_remote":        !opts.IsLocal(),
		"remote_id":        opts.RemoteID,
		"temp_file_prefix": opts.TempFilePrefix,
		"client_mode":      clientMode,
	})

	if opts.IsLocal() {
		logger = logger.WithField("local_temp_path", opts.LocalTempPath)
	} else {
		logger = logger.WithField("remote_temp_object", opts.RemoteTempObjectID)
	}

	logger.Info("saved file")
	fh.hashes = hashes.finish()
	return fh, nil
}

func (fh *FileHandler) newLocalFile(ctx context.Context, opts *UploadOpts) (consumer, error) {
	// make sure TempFolder exists
	err := os.MkdirAll(opts.LocalTempPath, 0700)
	if err != nil {
		return nil, fmt.Errorf("newLocalFile: mkdir %q: %v", opts.LocalTempPath, err)
	}

	file, err := ioutil.TempFile(opts.LocalTempPath, opts.TempFilePrefix)
	if err != nil {
		return nil, fmt.Errorf("newLocalFile: create file: %v", err)
	}

	go func() {
		<-ctx.Done()
		os.Remove(file.Name())
	}()

	fh.LocalPath = file.Name()
	return &filestore.LocalFile{File: file}, nil
}
