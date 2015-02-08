Rails.application.routes.draw do
  root to: 'users#show'

  get '/auth/:provider/callback' => 'sessions#create'
  resource :session, only: [:destroy]
end
