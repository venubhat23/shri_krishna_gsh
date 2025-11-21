# AWS Configuration
# Configure via environment variables:
# AWS_ACCESS_KEY_ID=your_access_key_id
# AWS_SECRET_ACCESS_KEY=your_secret_access_key
# AWS_REGION=ap-south-1

if Rails.env.production? && ENV['AWS_ACCESS_KEY_ID'].present?
  Aws.config.update({
    region: ENV['AWS_REGION'] || 'ap-south-1',
    credentials: Aws::Credentials.new(
      ENV['AWS_ACCESS_KEY_ID'],
      ENV['AWS_SECRET_ACCESS_KEY']
    )
  })
end