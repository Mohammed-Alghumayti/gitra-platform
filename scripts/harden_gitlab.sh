#!/bin/bash
# Applies GitLab security settings so the site can stay public safely.
# Run once on the GitLab VM after health_check.sh succeeds (cloud-init does this).
#   - Anyone can request an account, but an admin must approve it.
#   - 2FA is mandatory for every user (48h grace period to set it up).
#   - Passwords must be at least 12 characters.
#   - Projects can't be made public: code is visible to signed-in users only.
set -e

echo "=== Applying GitLab security settings ==="
docker exec gitlab_server gitlab-rails runner '
s = ApplicationSetting.current
s.update!(
  signup_enabled: true,
  require_admin_approval_after_user_signup: true,
  require_two_factor_authentication: true,
  two_factor_grace_period: 48,
  minimum_password_length: 12,
  default_project_visibility: Gitlab::VisibilityLevel::INTERNAL,
  default_group_visibility: Gitlab::VisibilityLevel::INTERNAL,
  restricted_visibility_levels: [Gitlab::VisibilityLevel::PUBLIC]
)
puts "signup_requires_approval=#{s.require_admin_approval_after_user_signup}"
puts "require_2fa=#{s.require_two_factor_authentication}"
puts "min_password_length=#{s.minimum_password_length}"
puts "public_visibility_blocked=#{s.restricted_visibility_levels.include?(Gitlab::VisibilityLevel::PUBLIC)}"
'

echo "✅ Security settings applied."
