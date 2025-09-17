# config/routes.rb
Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/jobs"

  get "/ingest", to: "webhooks#verify" # GET /ingest
  post "/ingest", to: "webhooks#create" # POST /ingest

  # optional debug/read-only endpoints
  # namespace :admin do
  #   resources :messages, only: [ :index, :show ]
  #   resources :media, only: [ :index, :show ]
  # end
end
