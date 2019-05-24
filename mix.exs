defmodule Mox.MixProject do
  use Mix.Project

  @version "0.5.1"

  def project do
    [
      app: :mox,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      name: "Mox",
      description: "Mocks and explicit contracts for Elixir",
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Mox.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :docs}
    ]
  end

  defp docs do
    [
      main: "Mox",
      source_ref: "v#{@version}",
      source_url: "https://github.com/plataformatec/mox"
    ]
  end

  defp package do
    %{
      licenses: ["Apache 2"],
      maintainers: ["José Valim"],
      links: %{"GitHub" => "https://github.com/plataformatec/mox"}
    }
  end
end
