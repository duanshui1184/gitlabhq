# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::BlobsResolver do
  include GraphqlHelpers

  describe '.resolver_complexity' do
    it 'adds one per path being resolved' do
      control = described_class.resolver_complexity({}, child_complexity: 1)

      expect(described_class.resolver_complexity({ paths: %w[a b c] }, child_complexity: 1))
        .to eq(control + 3)
    end
  end

  describe '#resolve' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, :repository) }

    let(:repository) { project.repository }
    let(:args) { { paths: paths, ref: ref } }
    let(:paths) { [] }
    let(:ref) { nil }

    subject(:resolve_blobs) { resolve(described_class, obj: repository, args: args, ctx: { current_user: user }) }

    context 'when unauthorized' do
      it 'generates an error' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolve_blobs
        end
      end
    end

    context 'when authorized' do
      before do
        project.add_developer(user)
      end

      context 'using no filter' do
        it 'returns nothing' do
          is_expected.to be_empty
        end
      end

      context 'using paths filter' do
        let(:paths) { ['README.md'] }

        it 'returns the specified blobs for HEAD' do
          is_expected.to contain_exactly(have_attributes(path: 'README.md'))
        end

        context 'specifying a non-existent blob' do
          let(:paths) { ['non-existent'] }

          it 'returns nothing' do
            is_expected.to be_empty
          end
        end

        context 'specifying a different ref' do
          let(:ref) { 'add-pdf-file' }
          let(:paths) { ['files/pdf/test.pdf', 'README.md'] }

          it 'returns the specified blobs for that ref' do
            is_expected.to contain_exactly(
              have_attributes(path: 'files/pdf/test.pdf'),
              have_attributes(path: 'README.md')
            )
          end
        end

        context 'when specifying an invalid ref' do
          let(:ref) { 'ma:in' }

          it 'raises an ArgumentError' do
            expect { resolve_blobs }.to raise_error(
              Gitlab::Graphql::Errors::ArgumentError,
              'Ref is not valid'
            )
          end
        end

        context 'when passing an empty ref' do
          let(:ref) { '' }

          it 'raises an ArgumentError' do
            expect { resolve_blobs }.to raise_error(
              Gitlab::Graphql::Errors::ArgumentError,
              'Ref is not valid'
            )
          end
        end
      end
    end
  end
end
