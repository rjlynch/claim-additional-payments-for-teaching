module OmniauthMockHelper
  def set_mock_auth(trn)
    omniauth_data = trn.nil? ? nil : OmniAuth::AuthHash.new(
      "extra" => {
        "raw_info" => {
          "trn" => trn
        }
      }
    )
    OmniAuth.config.mock_auth[:tid] = omniauth_data
    Rails.application.env_config["omniauth.auth"] = omniauth_data
  end
end