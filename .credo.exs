%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.MaxLineLength, [max_length: 120]}
      ]
    }
  ]
}
