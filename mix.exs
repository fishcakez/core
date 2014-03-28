defmodule Core.Mixfile do
  use Mix.Project

  def project do
    [ app: :core,
      version: "0.1.0",
      elixir: "~> 0.13.0-dev",
      deps: deps(Mix.env) ]
  end

  def application do
    [ applications: [],
      mod: { Core.App, [] }]
  end

  defp deps(:prod) do
    []
  end

  defp deps(_) do
    deps(:prod) ++ [ { :ex_doc, github: "elixir-lang/ex_doc" }]
  end

end
