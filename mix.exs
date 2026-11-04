defmodule Jexata.MixProject do
  use Mix.Project

  def project do
    [
      app: :jexata,
      version: "1.0.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      test_coverage: [summary: [threshold: 70]],
      description: "Native JSONata expression compiler and evaluator for Elixir",
      source_url: "https://github.com/Manuel1471/Jexata",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "CONTRIBUTING.md",
          "SECURITY.md",
          "docs/COMPATIBILITY.md",
          "docs/BENCHMARK.md",
          "docs/JSONATA_JS_COMPARISON.md",
          "docs/ARCHITECTURE.md"
        ]
      ],
      package: [
        files: [
          "lib",
          "mix.exs",
          "README.md",
          "CHANGELOG.md",
          "CONTRIBUTING.md",
          "SECURITY.md",
          "LICENSE",
          "docs"
        ],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/Manuel1471/Jexata"}
      ],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4.8", only: :dev, runtime: false}
    ]
  end
end
