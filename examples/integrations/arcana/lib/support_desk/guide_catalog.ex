defmodule SupportDesk.GuideCatalog do
  @moduledoc false

  @docs ~w(.md .markdown .livemd .txt .rst .adoc)
  @git_env [{"GH_PROMPT_DISABLED", "1"}, {"GIT_TERMINAL_PROMPT", "0"}]

  def entries(path) do
    ["package\trepository\tpackage_prefix" | rows] = path |> File.read!() |> String.split("\n", trim: true)

    for row <- rows do
      [package, repository, prefix] = String.split(row, "\t")
      %{package: package, repository: repository, prefix: prefix}
    end
  end

  def discover_public(entries, cache) do
    File.mkdir_p!(cache)

    sources =
      entries
      |> Enum.map(& &1.repository)
      |> Enum.uniq()
      |> parallel(fn repository -> {repository, public_repo(repository, cache)} end)
      |> Map.new()

    entries
    |> parallel(fn entry -> discover(entry, sources[entry.repository], hex_versions(entry.package)) end)
    |> List.flatten()
  end

  def discover(entry, repo, hex_versions) do
    with {:ok, checkout} <- repo,
         {:ok, tags} <- git(checkout, ["for-each-ref", "--format=%(refname:strip=2)", "refs/tags"]) do
      {published, errors} =
        case hex_versions do
          {:ok, versions} -> {versions, []}
          {:error, reason} -> {[], [%{package: entry.package, status: :repair_required, reason: reason}]}
        end

      by_version =
        tags
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&tag_version(&1, entry.package))
        |> Enum.sort_by(fn {_version, priority, tag} -> {priority, tag} end)
        |> Map.new(fn {version, _priority, tag} -> {version, tag} end)

      versions = Enum.sort(Enum.uniq(published ++ Map.keys(by_version)), Version)

      releases =
        versions
        |> Enum.map(&catalog_release(entry, checkout, &1, Map.get(by_version, &1), &1 in published))
        |> Enum.reject(&is_nil/1)

      case releases ++ errors do
        [] -> [%{package: entry.package, status: :no_releases}]
        found -> found
      end
    else
      {:error, reason} -> [%{package: entry.package, status: :repair_required, reason: reason}]
    end
  end

  defp catalog_release(entry, _repo, version, nil, true) do
    %{
      package: entry.package,
      version: version,
      discovery: [:hex],
      status: :repair_required,
      reason: :hex_release_has_no_matching_git_tag
    }
  end

  defp catalog_release(entry, repo, version, tag, hex?) do
    discovery = if hex?, do: [:hex, :git], else: [:git]
    release = %{package: entry.package, version: version, tag: tag, discovery: discovery}
    guides_root = if entry.prefix == ".", do: "guides", else: entry.prefix <> "/guides"

    with {:ok, commit} <- git(repo, ["rev-parse", "--verify", "refs/tags/" <> tag <> "^{commit}"]),
         commit = String.trim(commit),
         :ok <- check_package_root(entry.prefix, repo, commit),
         {:ok, listing} <- git(repo, ["ls-tree", "-r", "-z", "--name-only", commit, "--", guides_root <> "/"]) do
      paths = String.split(listing, <<0>>, trim: true)

      guides =
        for path <- paths, Path.extname(path) in @docs do
          source = "https://github.com/#{entry.repository}/blob/#{commit}/#{URI.encode(path)}"

          %{
            repo_path: repo,
            package: entry.package,
            version: version,
            tag: tag,
            commit: commit,
            path: "guides/" <> Path.relative_to(path, guides_root),
            git_path: path,
            source_url: source
          }
        end

      status = if guides == [], do: :no_guides, else: :ready

      Map.merge(release, %{
        commit: commit,
        status: status,
        guides: guides,
        skipped_assets: length(paths) - length(guides)
      })
    else
      {:error, :package_missing_at_tag} when not hex? -> nil
      {:error, reason} -> Map.merge(release, %{status: :repair_required, reason: reason})
    end
  end

  defp check_package_root(".", _repo, _commit), do: :ok

  defp check_package_root(prefix, repo, commit) do
    case git(repo, ["cat-file", "-e", commit <> ":" <> prefix <> "/mix.exs"]) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :package_missing_at_tag}
    end
  end

  defp tag_version(tag, package) do
    {candidate, priority} =
      case Enum.find([package <> "@", package <> "-", package <> "/"], &String.starts_with?(tag, &1)) do
        nil -> {tag, 0}
        prefix -> {String.replace_prefix(tag, prefix, ""), 1}
      end

    case Version.parse(String.replace_prefix(candidate, "v", "")) do
      {:ok, version} -> [{to_string(version), priority, tag}]
      :error -> []
    end
  end

  defp hex_versions(package) do
    url = "https://hex.pm/api/packages/" <> URI.encode(package)

    case System.cmd("curl", [
           "--silent",
           "--location",
           "--max-time",
           "15",
           "--retry",
           "2",
           "--write-out",
           "\n%{http_code}",
           url
         ]) do
      {response, 0} ->
        size = byte_size(response) - 4
        <<body::binary-size(^size), "\n", status::binary-size(3)>> = response
        hex_response(status, body)

      {_response, _code} ->
        {:error, :hex_request_failed}
    end
  end

  defp hex_response("200", body) do
    case Jason.decode(body) do
      {:ok, %{"releases" => releases}} -> {:ok, Enum.map(releases, & &1["version"])}
      _ -> {:error, :invalid_hex_response}
    end
  end

  defp hex_response("404", _body), do: {:ok, []}
  defp hex_response(status, _body), do: {:error, "Hex returned HTTP #{status}"}

  defp public_repo(repository, cache) do
    checkout = Path.join(cache, String.replace(repository, "/", "__") <> ".git")

    if File.regular?(Path.join(checkout, "HEAD")) do
      {:ok, checkout}
    else
      with {"public\n", 0} <- System.cmd("gh", ["api", "repos/" <> repository, "--jq", ".visibility"], env: @git_env),
           {_log, 0} <-
             System.cmd("gh", ["repo", "clone", repository, checkout, "--", "--bare"],
               env: @git_env,
               stderr_to_stdout: true
             ) do
        {:ok, checkout}
      else
        _ -> {:error, :public_repository_unavailable}
      end
    end
  end

  defp git(repo, args) do
    case System.cmd("git", ["-C", repo | args], env: @git_env, stderr_to_stdout: true) do
      {value, 0} -> {:ok, value}
      {_error, _code} -> {:error, :git_source_unavailable}
    end
  end

  defp parallel(items, fun) do
    items
    |> Task.async_stream(fun, max_concurrency: 6, timeout: :infinity)
    |> Enum.map(fn {:ok, value} -> value end)
  end
end
