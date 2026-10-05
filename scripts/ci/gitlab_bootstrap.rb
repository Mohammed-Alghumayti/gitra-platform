# Runs inside the GitLab container (gitlab-rails runner) from the deploy
# workflow. Prints KEY=VALUE lines the workflow reads.
#   ROOT_PASSWORD  - sets root's password (the GitHub secret is the source of truth)
#   NEED_RUNNER=1  - replaces the "gitra-runner" runner and prints its token
# Always prints a short-lived token used to push the demo app (revoked after).

root = User.find_by_username!('root')

password = ENV['ROOT_PASSWORD'].to_s
unless password.empty? || root.valid_password?(password)
  root.password = password
  root.password_confirmation = password
  root.password_automatically_set = false
  root.save!
  puts 'ROOT_PASSWORD_UPDATED=1'
end

unless ENV['SKIP_PAT'] == '1'
  root.personal_access_tokens.active.where(name: 'gitra-bootstrap').each(&:revoke!)
  pat = root.personal_access_tokens.create!(
    name: 'gitra-bootstrap',
    scopes: [:api, :write_repository],
    expires_at: 1.day.from_now
  )
  puts "PAT=#{pat.token}"
end

if ENV['NEED_RUNNER'] == '1'
  Ci::Runner.where(description: 'gitra-runner').find_each(&:destroy)
  runner = Ci::Runners::CreateRunnerService.new(
    user: root,
    params: { runner_type: 'instance_type', run_untagged: true, description: 'gitra-runner' }
  ).execute.payload[:runner]
  puts "RUNNER_TOKEN=#{runner.token}"
end
