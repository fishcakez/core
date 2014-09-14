defmodule Core.Mixfile do
  use Mix.Project

  def project do
    [ app: :core,
      version: "0.14.1",
      elixir: "~> 0.14.1 or ~> 0.15.0 or ~> 1.0.0 or ~> 1.1.0-dev",
      description: "Library for selective receive OTP processes",
      package: package(),
      deps: deps() ]
  end

  def application do
    [ applications: [],
      mod: { Core.App, [] }]
  end

  defp package() do
    [ contributors: ["James Fish"],
      licenses: ["Apache 2.0"],
      links: [{ "Github", "https://github.com/fishcakez/core" }] ]
  end

  defp deps() do
    [{ :ex_doc, ">= 0.5.2", only: [:docs]}]
  end

end
