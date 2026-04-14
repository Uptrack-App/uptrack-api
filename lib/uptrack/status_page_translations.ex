defmodule Uptrack.StatusPageTranslations do
  @moduledoc """
  Translations for public status page UI strings.

  Supports multiple languages for international status pages.
  """

  @translations %{
    "en" => %{
      # Overall status
      all_systems_operational: "All Systems Operational",
      partial_system_outage: "Partial System Outage",
      major_system_outage: "Major System Outage",
      system_status_unknown: "System Status Unknown",

      # Status descriptions
      all_services_running: "All %{count} services are running normally.",
      some_services_issues: "Some of our %{count} services are experiencing issues.",
      all_services_down: "All %{count} services are currently down.",
      unable_to_determine: "Unable to determine status for %{count} services.",

      # Monitor status
      operational: "Operational",
      down: "Down",
      issues: "Issues",
      unknown: "Unknown",

      # Sections
      services: "Services",
      recent_incidents: "Recent Incidents",
      subscribe_to_updates: "Subscribe to Updates",
      no_services_configured: "No Services Configured",
      no_services_message: "This status page doesn't have any services configured yet.",

      # Incidents
      ongoing: "Ongoing",
      resolved: "Resolved",

      # Subscribe form
      subscribe_description: "Get notified by email when incidents are reported or resolved.",
      email_placeholder: "your@email.com",
      subscribe_button: "Subscribe",
      check_email_verify: "Check your email to verify your subscription.",
      already_subscribed: "This email is already subscribed.",

      # Password form
      password_protected: "This status page is password protected.",
      enter_password: "Enter password",
      view_status: "View Status",
      incorrect_password: "Incorrect password",

      # Footer
      last_updated: "Last updated:",
      powered_by: "Powered by"
    },

    "de" => %{
      all_systems_operational: "Alle Systeme funktionieren",
      partial_system_outage: "Teilweiser Systemausfall",
      major_system_outage: "Schwerer Systemausfall",
      system_status_unknown: "Systemstatus unbekannt",

      all_services_running: "Alle %{count} Dienste laufen normal.",
      some_services_issues: "Einige unserer %{count} Dienste haben Probleme.",
      all_services_down: "Alle %{count} Dienste sind derzeit nicht erreichbar.",
      unable_to_determine: "Status für %{count} Dienste kann nicht ermittelt werden.",

      operational: "Betriebsbereit",
      down: "Ausgefallen",
      issues: "Probleme",
      unknown: "Unbekannt",

      services: "Dienste",
      recent_incidents: "Aktuelle Vorfalle",
      subscribe_to_updates: "Updates abonnieren",
      no_services_configured: "Keine Dienste konfiguriert",
      no_services_message: "Diese Statusseite hat noch keine konfigurierten Dienste.",

      ongoing: "Aktiv",
      resolved: "Behoben",

      subscribe_description: "Erhalten Sie E-Mail-Benachrichtigungen bei Vorfallen.",
      email_placeholder: "ihre@email.de",
      subscribe_button: "Abonnieren",
      check_email_verify: "Prufen Sie Ihre E-Mail, um Ihr Abonnement zu bestatigen.",
      already_subscribed: "Diese E-Mail ist bereits abonniert.",

      password_protected: "Diese Statusseite ist passwortgeschutzt.",
      enter_password: "Passwort eingeben",
      view_status: "Status anzeigen",
      incorrect_password: "Falsches Passwort",

      last_updated: "Zuletzt aktualisiert:",
      powered_by: "Betrieben von"
    },

    "fr" => %{
      all_systems_operational: "Tous les systemes sont operationnels",
      partial_system_outage: "Panne partielle du systeme",
      major_system_outage: "Panne majeure du systeme",
      system_status_unknown: "Statut du systeme inconnu",

      all_services_running: "Les %{count} services fonctionnent normalement.",
      some_services_issues: "Certains de nos %{count} services rencontrent des problemes.",
      all_services_down: "Tous les %{count} services sont actuellement indisponibles.",
      unable_to_determine: "Impossible de determiner le statut de %{count} services.",

      operational: "Operationnel",
      down: "Hors service",
      issues: "Problemes",
      unknown: "Inconnu",

      services: "Services",
      recent_incidents: "Incidents recents",
      subscribe_to_updates: "S'abonner aux mises a jour",
      no_services_configured: "Aucun service configure",
      no_services_message: "Cette page de statut n'a pas encore de services configures.",

      ongoing: "En cours",
      resolved: "Resolu",

      subscribe_description: "Recevez des notifications par e-mail lors d'incidents.",
      email_placeholder: "votre@email.fr",
      subscribe_button: "S'abonner",
      check_email_verify: "Verifiez votre e-mail pour confirmer votre abonnement.",
      already_subscribed: "Cet e-mail est deja abonne.",

      password_protected: "Cette page de statut est protegee par mot de passe.",
      enter_password: "Entrer le mot de passe",
      view_status: "Voir le statut",
      incorrect_password: "Mot de passe incorrect",

      last_updated: "Derniere mise a jour :",
      powered_by: "Propulse par"
    },

    "es" => %{
      all_systems_operational: "Todos los sistemas operativos",
      partial_system_outage: "Interrupcion parcial del sistema",
      major_system_outage: "Interrupcion mayor del sistema",
      system_status_unknown: "Estado del sistema desconocido",

      all_services_running: "Los %{count} servicios funcionan normalmente.",
      some_services_issues: "Algunos de nuestros %{count} servicios tienen problemas.",
      all_services_down: "Todos los %{count} servicios estan caidos.",
      unable_to_determine: "No se puede determinar el estado de %{count} servicios.",

      operational: "Operativo",
      down: "Caido",
      issues: "Problemas",
      unknown: "Desconocido",

      services: "Servicios",
      recent_incidents: "Incidentes recientes",
      subscribe_to_updates: "Suscribirse a actualizaciones",
      no_services_configured: "No hay servicios configurados",
      no_services_message: "Esta pagina de estado aun no tiene servicios configurados.",

      ongoing: "En curso",
      resolved: "Resuelto",

      subscribe_description: "Reciba notificaciones por correo electronico sobre incidentes.",
      email_placeholder: "su@email.es",
      subscribe_button: "Suscribirse",
      check_email_verify: "Revise su correo para verificar su suscripcion.",
      already_subscribed: "Este correo ya esta suscrito.",

      password_protected: "Esta pagina de estado esta protegida con contrasena.",
      enter_password: "Ingrese la contrasena",
      view_status: "Ver estado",
      incorrect_password: "Contrasena incorrecta",

      last_updated: "Ultima actualizacion:",
      powered_by: "Impulsado por"
    },

    "pt-BR" => %{
      all_systems_operational: "Todos os sistemas operacionais",
      partial_system_outage: "Interrupcao parcial do sistema",
      major_system_outage: "Interrupcao grave do sistema",
      system_status_unknown: "Status do sistema desconhecido",

      all_services_running: "Todos os %{count} servicos estao funcionando normalmente.",
      some_services_issues: "Alguns dos nossos %{count} servicos estao com problemas.",
      all_services_down: "Todos os %{count} servicos estao fora do ar.",
      unable_to_determine: "Nao foi possivel determinar o status de %{count} servicos.",

      operational: "Operacional",
      down: "Fora do ar",
      issues: "Problemas",
      unknown: "Desconhecido",

      services: "Servicos",
      recent_incidents: "Incidentes recentes",
      subscribe_to_updates: "Inscrever-se para atualizacoes",
      no_services_configured: "Nenhum servico configurado",
      no_services_message: "Esta pagina de status ainda nao tem servicos configurados.",

      ongoing: "Em andamento",
      resolved: "Resolvido",

      subscribe_description: "Receba notificacoes por e-mail sobre incidentes.",
      email_placeholder: "seu@email.com.br",
      subscribe_button: "Inscrever-se",
      check_email_verify: "Verifique seu e-mail para confirmar sua inscricao.",
      already_subscribed: "Este e-mail ja esta inscrito.",

      password_protected: "Esta pagina de status e protegida por senha.",
      enter_password: "Digite a senha",
      view_status: "Ver status",
      incorrect_password: "Senha incorreta",

      last_updated: "Ultima atualizacao:",
      powered_by: "Desenvolvido por"
    },

    "ja" => %{
      all_systems_operational: "全システム正常稼働中",
      partial_system_outage: "一部システム障害発生中",
      major_system_outage: "重大なシステム障害発生中",
      system_status_unknown: "システム状態不明",

      all_services_running: "%{count}件のサービスが正常に稼働しています。",
      some_services_issues: "%{count}件のサービスの一部に問題が発生しています。",
      all_services_down: "%{count}件のサービスが現在停止中です。",
      unable_to_determine: "%{count}件のサービスの状態を確認できません。",

      operational: "正常",
      down: "停止中",
      issues: "問題あり",
      unknown: "不明",

      services: "サービス",
      recent_incidents: "最近のインシデント",
      subscribe_to_updates: "更新を購読",
      no_services_configured: "サービスが設定されていません",
      no_services_message: "このステータスページにはまだサービスが設定されていません。",

      ongoing: "対応中",
      resolved: "解決済み",

      subscribe_description: "インシデント発生時にメール通知を受け取ります。",
      email_placeholder: "your@email.jp",
      subscribe_button: "購読する",
      check_email_verify: "メールを確認して購読を確定してください。",
      already_subscribed: "このメールアドレスは既に購読済みです。",

      password_protected: "このステータスページはパスワードで保護されています。",
      enter_password: "パスワードを入力",
      view_status: "ステータスを表示",
      incorrect_password: "パスワードが正しくありません",

      last_updated: "最終更新:",
      powered_by: "Powered by"
    },

    "zh" => %{
      all_systems_operational: "所有系统运行正常",
      partial_system_outage: "部分系统中断",
      major_system_outage: "严重系统中断",
      system_status_unknown: "系统状态未知",

      all_services_running: "所有 %{count} 个服务运行正常。",
      some_services_issues: "部分 %{count} 个服务遇到问题。",
      all_services_down: "所有 %{count} 个服务目前不可用。",
      unable_to_determine: "无法确定 %{count} 个服务的状态。",

      operational: "正常运行",
      down: "已停止",
      issues: "有问题",
      unknown: "未知",

      services: "服务",
      recent_incidents: "最近事件",
      subscribe_to_updates: "订阅更新",
      no_services_configured: "未配置服务",
      no_services_message: "此状态页面尚未配置任何服务。",

      ongoing: "进行中",
      resolved: "已解决",

      subscribe_description: "通过邮件接收事件通知。",
      email_placeholder: "your@email.cn",
      subscribe_button: "订阅",
      check_email_verify: "请查收邮件以验证订阅。",
      already_subscribed: "该邮箱已订阅。",

      password_protected: "此状态页面受密码保护。",
      enter_password: "输入密码",
      view_status: "查看状态",
      incorrect_password: "密码错误",

      last_updated: "最后更新:",
      powered_by: "技术支持"
    }
  }

  @supported_languages Map.keys(@translations)

  @doc """
  Returns list of supported language codes.
  """
  def supported_languages, do: @supported_languages

  @doc """
  Gets a translation for a given key and language.
  Falls back to English if the language or key is not found.
  """
  def t(key, lang \\ "en", bindings \\ %{})

  def t(key, lang, bindings) when is_atom(key) do
    lang = normalize_language(lang)

    text =
      @translations
      |> Map.get(lang, @translations["en"])
      |> Map.get(key, Map.get(@translations["en"], key, to_string(key)))

    interpolate(text, bindings)
  end

  def t(key, lang, bindings) when is_binary(key) do
    t(String.to_existing_atom(key), lang, bindings)
  rescue
    ArgumentError -> key
  end

  @doc """
  Normalizes a language code to a supported language.
  Handles variants like "en-US" -> "en", "pt-BR" -> "pt-BR", "pt" -> "pt-BR".
  """
  def normalize_language(nil), do: "en"
  def normalize_language(""), do: "en"

  def normalize_language(lang) when is_binary(lang) do
    # Normalize casing and check for exact match first (handles "pt-BR")
    normalized = String.downcase(lang) |> String.replace("_", "-")

    cond do
      normalized in @supported_languages ->
        normalized

      # Map "pt" or "pt-*" variants to "pt-BR"
      String.starts_with?(normalized, "pt") ->
        if "pt-BR" in @supported_languages, do: "pt-BR", else: "en"

      true ->
        base = normalized |> String.split("-") |> List.first()
        if base in @supported_languages, do: base, else: "en"
    end
  end

  def normalize_language(_), do: "en"

  @doc """
  Detects the preferred language from Accept-Language header.
  """
  def detect_language(accept_language) when is_binary(accept_language) do
    accept_language
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, q} -> -q end)
    |> Enum.find_value("en", fn {lang, _q} ->
      normalized = normalize_language(lang)
      if normalized != "en" || lang =~ ~r/^en/i, do: normalized
    end)
  end

  def detect_language(_), do: "en"

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang] ->
        {lang, 1.0}

      [lang | rest] ->
        q =
          rest
          |> Enum.find_value(1.0, fn part ->
            case String.trim(part) do
              "q=" <> value ->
                case Float.parse(value) do
                  {f, _} -> f
                  :error -> 1.0
                end

              _ ->
                nil
            end
          end)

        {lang, q}
    end
  end

  defp interpolate(text, bindings) when is_binary(text) and map_size(bindings) > 0 do
    Enum.reduce(bindings, text, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp interpolate(text, _), do: text
end
