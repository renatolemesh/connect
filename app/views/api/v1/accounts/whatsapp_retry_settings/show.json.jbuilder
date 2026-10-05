json.enabled @setting.enabled
json.config @setting.effective_config
json.last_run_at @setting.last_run_at
json.last_run_summary @setting.last_run_summary
json.available_inboxes do
  json.array!(Current.account.inboxes.where(channel_type: %w[Channel::Whatsapp Channel::Api]).order(:name)) do |inbox|
    json.id inbox.id
    json.name inbox.name
    json.channel_type inbox.channel_type
    json.official inbox.channel_type == 'Channel::Whatsapp'
  end
end
