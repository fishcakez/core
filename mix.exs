defmodule Core.Mixfile do
  use Mix.Project

  def project do
    [ app: :core,
      version: "0.14.0",
      elixir: "~> 0.14.1",
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
    [{ :ex_doc, github: "elixir-lang/ex_doc", only: [:docs]}]
  end

end
