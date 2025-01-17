# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User Cluster', :js do
  include GoogleApi::CloudPlatformHelpers

  let(:project) { create(:project) }
  let(:user) { create(:user) }

  before do
    project.add_maintainer(user)
    gitlab_sign_in(user)

    allow(Projects::ClustersController).to receive(:STATUS_POLLING_INTERVAL) { 100 }
    allow_next_instance_of(Clusters::Kubernetes::CreateOrUpdateNamespaceService) do |instance|
      allow(instance).to receive(:execute)
    end
    allow_next_instance_of(Clusters::Cluster) do |instance|
      allow(instance).to receive(:retrieve_connection_status).and_return(:connected)
    end
  end

  context 'when user does not have a cluster and visits cluster index page' do
    before do
      visit project_clusters_path(project)

      click_link 'Certificate'
      click_link 'Connect with a certificate'
    end

    context 'when user filled form with valid parameters' do
      before do
        fill_in 'cluster_name', with: 'dev-cluster'
        fill_in 'cluster_platform_kubernetes_attributes_api_url', with: 'http://example.com'
        fill_in 'cluster_platform_kubernetes_attributes_token', with: 'my-token'
      end

      subject { click_button 'Add Kubernetes cluster' }

      it 'user sees a cluster details page' do
        subject

        expect(page).to have_content('GitLab Integration')
        expect(page.find_field('cluster[name]').value).to eq('dev-cluster')
        expect(page.find_field('cluster[platform_kubernetes_attributes][api_url]').value)
          .to have_content('http://example.com')
        expect(page.find_field('cluster[platform_kubernetes_attributes][token]').value)
          .to be_empty
      end

      it 'user sees RBAC is enabled by default' do
        expect(page).to have_checked_field('RBAC-enabled cluster')
      end

      it 'user sees namespace per environment is enabled by default' do
        expect(page).to have_checked_field('Namespace per environment')
      end
    end

    context 'when user filled form with invalid parameters' do
      before do
        click_button 'Add Kubernetes cluster'
      end

      it 'user sees a validation error' do
        expect(page).to have_css('.gl-field-error')
      end
    end
  end

  context 'when user does have a cluster and visits cluster page' do
    let(:cluster) { create(:cluster, :provided_by_user, projects: [project]) }

    before do
      visit project_cluster_path(project, cluster)
    end

    it 'user sees a cluster details page' do
      expect(page).to have_content('GitLab Integration')
      expect(page).to have_button('Save changes')
    end

    include_examples "user disables a cluster"

    context 'when user changes cluster parameters' do
      before do
        fill_in 'cluster_name', with: 'my-dev-cluster'
        fill_in 'cluster_platform_kubernetes_attributes_namespace', with: 'my-namespace'
        page.within('.js-provider-details') { click_button 'Save changes' }
      end

      it 'user sees the successful message' do
        expect(page).to have_content('Kubernetes cluster was successfully updated.')
        expect(cluster.reload.name).to eq('my-dev-cluster')
        expect(cluster.reload.platform_kubernetes.namespace).to eq('my-namespace')
      end
    end

    context 'when user destroys the cluster' do
      before do
        click_link 'Advanced Settings'
        click_button 'Remove integration and resources'
        fill_in 'confirm_cluster_name_input', with: cluster.name
        click_button 'Remove integration'
        click_link 'Certificate'
      end

      it 'user sees creation form with the successful message' do
        expect(page).to have_content('Kubernetes cluster integration was successfully removed.')
        expect(page).to have_link('Connect with a certificate')
      end
    end
  end
end
