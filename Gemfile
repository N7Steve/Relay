source "https://rubygems.org"

ruby file: ".ruby-version"

# Rails
gem "rails", "~> 8.1.0"

# Drivers
gem "pg", "~> 1.5"
gem "redis", "~> 5.4"

# Deployment
gem "puma", ">= 7.2.1"
gem "bootsnap", require: false

# Assets
gem "importmap-rails"
gem "propshaft"
gem "tailwindcss-rails"
gem "lucide-rails"

# Hotwire + UI
gem "stimulus-rails"
gem "turbo-rails"
gem "view_component"

# https://github.com/lookbook-hq/lookbook/issues/712
# TODO: Remove max version constraint when fixed
gem "lookbook", "2.3.11"

gem "hotwire_combobox"

# Background Jobs
gem "connection_pool", "~> 3.0" # pin to 2.x; 3.0 breaks sidekiq 8.x
gem "sidekiq"
gem "sidekiq-cron"
gem "sidekiq-unique-jobs"

# Active Storage
gem "image_processing", ">= 1.2"

# Other
gem "ostruct"
gem "bcrypt", "~> 3.1"
gem "jwt"
gem "jbuilder"
gem "countries"

# OAuth & API Security
gem "doorkeeper"
gem "rack-attack", "~> 6.6"
gem "rack-cors"
gem "pundit"
gem "faraday"
gem "faraday-retry"
gem "faraday-multipart"
gem "inline_svg"
gem "octokit"
gem "pagy"
gem "rails-i18n"
gem "rails-settings-cached"
gem "tzinfo-data", platforms: %i[mswin mswin64 mingw x64_mingw jruby]
gem "csv"
gem "rchardet" # Character encoding detection
gem "redcarpet"
gem "httparty"
gem "rotp", "~> 6.3"
gem "rqrcode", "~> 3.0"
gem "webauthn", "~> 3.4"
gem "activerecord-import"
gem "rubyzip", "~> 3.4"

# OpenID Connect, OAuth & SAML authentication
gem "omniauth", "~> 2.1"
gem "omniauth-rails_csrf_protection", ">= 2.0"
gem "omniauth_openid_connect"
gem "omniauth-google-oauth2"
gem "omniauth-github"
gem "omniauth-saml", "~> 2.1"

# State machines
gem "aasm"
gem "after_commit_everywhere", "~> 1.0"


group :development, :test do
  gem "debug", platforms: %i[mri mswin mswin64 mingw x64_mingw]
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "i18n-tasks"
  gem "erb_lint"
  gem "dotenv-rails"
end

if ENV["BENCHMARKING_ENABLED"]
  gem "dotenv-rails", groups: [ :production ]
end

group :development do
  gem "hotwire-livereload"
  gem "letter_opener"
  gem "ruby-lsp-rails"
  gem "web-console"
  gem "faker"
  gem "foreman"
end

group :development, :test do
  gem "rspec-rails"
  gem "rswag-api"
  gem "rswag-specs"
  gem "rswag-ui"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "mocha"
  gem "vcr"
  gem "webmock"
  gem "climate_control"
  gem "simplecov", require: false
end
