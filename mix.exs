Code.ensure_loaded?(Hex) and Hex.start

defmodule Core.Mixfile do
  use Mix.Project

  def project do
    [ app: :core,
      version: "0.13.1",
      elixir: "~> 0.13.2",
      description: "Library for selective receive OTP processes",
      package: package(),
      deps: deps(Mix.env) ]
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

  defp deps(:prod) do
    []
  end

  defp deps(_) do
    deps(:prod) ++ [ { :ex_doc, github: "elixir-lang/ex_doc" }]
  end

end
