defmodule Mox.MixProject do
  use Mix.Project

  @version "1.0.1"

  def project do
    [
      app: :mox,
      version: @version,
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.16", only: :docs}
    ]
  end

  defp docs do
    [
      main: "Mox",
      source_ref: "v#{@version}",
      source_url: "https://github.com/dashbitco/mox"
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      maintainers: ["José Valim"],
      links: %{"GitHub" => "https://github.com/dashbitco/mox"}
    }
  end
end
