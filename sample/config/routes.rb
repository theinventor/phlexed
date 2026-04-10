Rails.application.routes.draw do
  root "home#index"

  get  "dashboard",      to: "dashboard#index"
  get  "settings",       to: "settings#index"
  patch "settings",      to: "settings#update"

  # Profile (Phlex-converted already — used as the "target state" example)
  resource :profile, only: [:show, :edit, :update]
end
