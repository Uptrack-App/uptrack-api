defmodule Mix.Tasks.TranslatePo do
  @shortdoc "Translates untranslated Gettext .po files using DeepL API"
  @moduledoc """
  Translates all untranslated msgid strings in .po files using the DeepL API.

  Requires DEEPL_API_KEY environment variable (use :fx suffix for free tier).

  ## Usage

      DEEPL_API_KEY=your_key mix translate_po

  ## Options

      --locale   Only translate a specific locale (e.g. --locale ja)
      --domain   Only translate a specific domain (e.g. --domain errors)
      --dry-run  Print translations without writing files

  Skips strings that already have a translation (non-empty msgstr).
  Safe to re-run — only translates new/empty strings.
  """

  use Mix.Task

  @deepl_url "https://api-free.deepl.com/v2/translate"

  # Map Gettext locale folder names → DeepL target language codes
  @locale_to_deepl %{
    "ja" => "JA",
    "de" => "DE",
    "es" => "ES",
    "pt_BR" => "PT-BR"
  }

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [locale: :string, domain: :string, dry_run: :boolean]
      )

    api_key = System.get_env("DEEPL_API_KEY") || Mix.raise("DEEPL_API_KEY env var is required")

    filter_locale = opts[:locale]
    filter_domain = opts[:domain]
    dry_run = opts[:dry_run] || false

    locales =
      if filter_locale do
        [filter_locale]
      else
        Map.keys(@locale_to_deepl)
      end

    for locale <- locales do
      deepl_lang = Map.fetch!(@locale_to_deepl, locale)
      po_dir = Path.join(["priv/gettext", locale, "LC_MESSAGES"])

      if File.dir?(po_dir) do
        domains =
          po_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".po"))
          |> Enum.map(&String.replace_suffix(&1, ".po", ""))

        domains =
          if filter_domain do
            Enum.filter(domains, &(&1 == filter_domain))
          else
            domains
          end

        for domain <- domains do
          po_path = Path.join(po_dir, "#{domain}.po")
          Mix.shell().info("Translating #{po_path} → #{deepl_lang}")
          translate_file(po_path, deepl_lang, api_key, dry_run)
        end
      end
    end

    Mix.shell().info("Done.")
  end

  defp translate_file(path, deepl_lang, api_key, dry_run) do
    content = File.read!(path)
    entries = parse_po_entries(content)

    untranslated =
      Enum.filter(entries, fn entry ->
        not entry.plural and entry.msgstr == "" and entry.msgid != ""
      end)

    untranslated_plural =
      Enum.filter(entries, fn entry ->
        entry.plural and (entry.msgstr == "" or entry.msgstr_0 == "") and entry.msgid != ""
      end)

    if untranslated == [] and untranslated_plural == [] do
      Mix.shell().info("  ✓ All strings already translated, skipping")
    else
      Mix.shell().info("  Translating #{length(untranslated) + length(untranslated_plural)} strings...")
      new_content = translate_po_content(content, untranslated, untranslated_plural, deepl_lang, api_key, dry_run)

      unless dry_run do
        File.write!(path, new_content)
        Mix.shell().info("  ✓ Written")
      end
    end
  end

  defp translate_po_content(content, untranslated, untranslated_plural, deepl_lang, api_key, dry_run) do
    result = content

    # Translate singular strings
    result =
      Enum.reduce(untranslated, result, fn entry, acc ->
        translated = deepl_translate(entry.msgid, deepl_lang, api_key)

        if dry_run do
          Mix.shell().info("  [#{entry.msgid}] → [#{translated}]")
          acc
        else
          # Replace empty msgstr "" with the translation after the msgid line
          String.replace(
            acc,
            "msgid \"#{entry.msgid}\"\nmsgstr \"\"",
            "msgid \"#{entry.msgid}\"\nmsgstr \"#{escape_po(translated)}\"",
            global: false
          )
        end
      end)

    # Translate plural strings — translate singular form, use for all plural forms
    result =
      Enum.reduce(untranslated_plural, result, fn entry, acc ->
        translated = deepl_translate(entry.msgid, deepl_lang, api_key)

        if dry_run do
          Mix.shell().info("  [#{entry.msgid}] → [#{translated}]")
          acc
        else
          String.replace(
            acc,
            "msgid \"#{entry.msgid}\"\nmsgid_plural \"#{entry.msgid_plural}\"\nmsgstr[0] \"\"",
            "msgid \"#{entry.msgid}\"\nmsgid_plural \"#{entry.msgid_plural}\"\nmsgstr[0] \"#{escape_po(translated)}\"",
            global: false
          )
        end
      end)

    result
  end

  defp deepl_translate(text, target_lang, api_key) do
    # DeepL requires header-based auth (form body deprecated Nov 2025)
    body =
      Jason.encode!(%{
        "text" => [text],
        "target_lang" => target_lang,
        "source_lang" => "EN",
        "preserve_formatting" => true
      })

    headers = [
      {~c"Authorization", "DeepL-Auth-Key #{api_key}" |> String.to_charlist()},
      {~c"Content-Type", ~c"application/json"}
    ]

    case :httpc.request(
           :post,
           {@deepl_url |> String.to_charlist(), headers, ~c"application/json",
            body |> String.to_charlist()},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        resp_body
        |> :binary.list_to_bin()
        |> Jason.decode!()
        |> get_in(["translations", Access.at(0), "text"])
        |> String.trim()

      {:ok, {{_, status, _}, _, resp_body}} ->
        Mix.shell().error("DeepL error #{status}: #{:binary.list_to_bin(resp_body)}")
        ""

      {:error, reason} ->
        Mix.shell().error("HTTP error: #{inspect(reason)}")
        ""
    end
  end

  defp parse_po_entries(content) do
    # Extract msgid/msgstr pairs for singular entries
    singular =
      Regex.scan(~r/msgid "(.+?)"\nmsgstr "([^"]*)"/, content, capture: :all_but_first)
      |> Enum.map(fn [msgid, msgstr] ->
        %{plural: false, msgid: unescape_po(msgid), msgstr: msgstr}
      end)

    # Extract plural entries
    plural =
      Regex.scan(
        ~r/msgid "(.+?)"\nmsgid_plural "(.+?)"\nmsgstr\[0\] "([^"]*)"/,
        content,
        capture: :all_but_first
      )
      |> Enum.map(fn [msgid, msgid_plural, msgstr_0] ->
        %{
          plural: true,
          msgid: unescape_po(msgid),
          msgid_plural: unescape_po(msgid_plural),
          msgstr_0: msgstr_0,
          msgstr: msgstr_0
        }
      end)

    singular ++ plural
  end

  defp escape_po(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp unescape_po(str) do
    str
    |> String.replace("\\n", "\n")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\\\", "\\")
  end
end
