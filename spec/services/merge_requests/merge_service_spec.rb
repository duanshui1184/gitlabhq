require 'spec_helper'

describe MergeRequests::MergeService do
  let(:user) { create(:user) }
  let(:user2) { create(:user) }
  let(:merge_request) { create(:merge_request, assignee: user2) }
  let(:project) { merge_request.project }

  before do
    project.team << [user, :master]
    project.team << [user2, :developer]
  end

  describe :execute do
    let(:service) { MergeRequests::MergeService.new(project, user, {}) }

    context 'valid params' do
      before do
        allow(service).to receive(:execute_hooks)

        service.execute(merge_request, 'Awesome message')
      end

      it { expect(merge_request).to be_valid }
      it { expect(merge_request).to be_merged }

      it 'should send email to user2 about merge of new merge_request' do
        email = ActionMailer::Base.deliveries.last
        expect(email.to.first).to eq(user2.email)
        expect(email.subject).to include(merge_request.title)
      end

      it 'should create system note about merge_request merge' do
        note = merge_request.notes.last
        expect(note.note).to include 'Status changed to merged'
      end
    end

    context "something goes wrong" do
      it "mark merge request as open" do
        allow(service).to receive(:commit).and_return(false)
        merge_request.merging
        service.execute(merge_request, 'Awesome message')
        expect(merge_request.state).to eq("opened")
      end
    end
  end
end
