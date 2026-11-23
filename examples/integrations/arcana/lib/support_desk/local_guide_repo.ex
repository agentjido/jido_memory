defmodule SupportDesk.LocalGuideRepo do
  @moduledoc false

  def with_releases(releases, fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido-memory-guides-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(root)

    try do
      git!(root, ["init", "--quiet"])
      refs = Map.new(releases, fn {version, files} -> {version, commit(root, version, files)} end)
      fun.(root, refs)
    after
      File.rm_rf!(root)
    end
  end

  defp commit(root, version, files) do
    File.rm_rf!(Path.join(root, "guides"))

    Enum.each(files, fn {relative, text} ->
      path = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, text)
    end)

    git!(root, ["add", "--all"])

    git!(root, [
      "-c",
      "commit.gpgsign=false",
      "-c",
      "user.name=Jido Memory Example",
      "-c",
      "user.email=example@example.test",
      "commit",
      "--quiet",
      "--allow-empty",
      "-m",
      version
    ])

    git!(root, ["-c", "tag.gpgsign=false", "tag", version])
    git!(root, ["rev-parse", "refs/tags/" <> version <> "^{commit}"])
  end

  defp git!(root, args) do
    {output, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    String.trim(output)
  end
end
