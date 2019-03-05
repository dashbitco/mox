defmodule MoxExample do
  @example_api Application.get_env(
                                          :mox_example,
                                          :example_api,
                                          ExampleAPI
                                        )
  def post_name(name) do
    # run api-post/3 in our currently selected implementation
    @example_api.api_post(name, [], [])
  end
end

defmodule ExampleAPI do
  alias HTTPoison
  @callback api_post(String.t(), [], []) :: {:ok, nil} | {:error, any()}
  def api_post(body \\ "", headers, options) do
    # if I don't mock this then this is an integration test!
    HTTPoison.post("http://example.com", body, headers, options)
  end
end
