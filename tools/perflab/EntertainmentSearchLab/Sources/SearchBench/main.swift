import SearchLab
print(runSearchBenchmark(queryCount: CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100))
