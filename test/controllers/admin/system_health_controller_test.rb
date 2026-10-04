require "test_helper"

class Admin::SystemHealthControllerTest < ActionDispatch::IntegrationTest
  test "super admin can view background diagnostics without an AI tab" do
    sign_in users(:sure_support_staff)
    get admin_system_health_url
    assert_response :success
    assert_select "a[href*='tab=ai']", count: 0
  end

  test "renders degraded state with reason when Sidekiq is unhealthy" do
    sign_in users(:sure_support_staff)
    SidekiqHealth.any_instance.stubs(:healthy?).returns(false)
    SidekiqHealth.any_instance.stubs(:reason).returns(:no_worker_processes)
    SidekiqHealth.any_instance.stubs(:processes_count).returns(0)
    SidekiqHealth.any_instance.stubs(:last_heartbeat_at).returns(nil)
    SidekiqHealth.any_instance.stubs(:max_queue_latency).returns(0.0)
    SidekiqHealth.any_instance.stubs(:enqueued_count).returns(7)
    SidekiqHealth.any_instance.stubs(:retry_count).returns(0)
    SidekiqHealth.any_instance.stubs(:failed_count).returns(0)
    SidekiqHealth.any_instance.stubs(:processed_count).returns(0)
    SidekiqHealth.any_instance.stubs(:queue_breakdown).returns([])

    get admin_system_health_url

    assert_response :success
    assert_match(/Degraded/, response.body)
    assert_match(/No Sidekiq worker process is connected/, response.body)
  end

  test "German background job translations are present without fallback" do
    keys = %w[
      title tabs.background_jobs tabs.ai alert.title
      status_section_title status_section_description counters_section_title
      counters_section_description queues_section_title queues_section_description
      labels.status labels.processes labels.last_heartbeat labels.max_queue_latency
      labels.enqueued labels.retries labels.failed labels.processed_total
      labels.queue labels.size labels.latency values.healthy values.unhealthy
      values.never values.no_queues
    ]
    keys.each do |key|
      assert_kind_of String, I18n.t("admin.system_health.show.#{key}", locale: :de, fallback: false, raise: true)
    end
    assert_equal "vor 2 Minuten", I18n.t("admin.system_health.show.values.time_ago", locale: :de,
      fallback: false, raise: true, time_ago: "2 Minuten")
    assert_equal "1,5 s", I18n.t("admin.system_health.show.values.seconds", locale: :de,
      fallback: false, raise: true, seconds: "1,5")
  end

  test "German super admin sees localized background job statistics" do
    users(:sure_support_staff).update!(locale: "de")
    sign_in users(:sure_support_staff)
    stub_healthy_sidekiq

    travel_to Time.current do
      SidekiqHealth.any_instance.stubs(:last_heartbeat_at).returns(2.minutes.ago)
      SidekiqHealth.any_instance.stubs(:queue_breakdown).returns([ [ "default", 1234, 1.5 ] ])
      get admin_system_health_url
    end

    assert_response :success
    assert_select "h1", text: "Systemstatus"
    assert_select "button[role='tab'][aria-selected='true']", text: "Hintergrundaufgaben"
    assert_select "button[role='tab']", text: "KI-Status", count: 0
    assert_select "h2", text: "Sidekiq-Status"
    assert_select "h2", text: "Aufgabenstatistik"
    assert_select "h2", text: "Warteschlangen"
    assert_select "dd", text: "Funktionsfähig"
    assert_select "dd", text: "vor 2 Minuten"
    {
      "Status" => "Funktionsfähig", "Worker-Prozesse" => "1",
      "Letztes Lebenszeichen" => "vor 2 Minuten", "Längste Wartezeit" => "0,0 s",
      "In der Warteschlange" => "0", "Zur Wiederholung vorgemerkt" => "0",
      "Fehlgeschlagen" => "0", "Insgesamt verarbeitet" => "42"
    }.each do |label, value|
      assert_select "dl > div" do |items|
        item = items.find { |element| element.at_css("dt")&.text == label }
        assert item, "Missing statistic: #{label}"
        assert_equal value, item.at_css("dd").text.strip
      end
    end
    assert_select "th", text: "Anzahl der Aufgaben"
    assert_select "th", text: "Wartezeit"
    assert_select "td", text: "default"
    assert_select "td", text: "1.234"
    assert_select "td", text: "1,5 s"
  end

  test "German background job statistics show degraded and empty states" do
    users(:sure_support_staff).update!(locale: "de")
    sign_in users(:sure_support_staff)
    stub_healthy_sidekiq
    SidekiqHealth.any_instance.stubs(:healthy?).returns(false)
    SidekiqHealth.any_instance.stubs(:reason).returns(:no_worker_processes)
    SidekiqHealth.any_instance.stubs(:last_heartbeat_at).returns(nil)
    SidekiqHealth.any_instance.stubs(:queue_breakdown).returns([])

    get admin_system_health_url

    assert_response :success
    assert_select "dd", text: "Beeinträchtigt"
    assert_select "dd", text: "Nie"
    assert_match "Hintergrundaufgaben werden nicht ausgeführt", response.body
    assert_select "p", text: "Es sind keine Warteschlangen registriert. Möglicherweise läuft der Worker nicht."
  end

  test "non super admin is redirected away" do
    users(:family_admin).update!(locale: "de")
    sign_in users(:family_admin)

    get admin_system_health_url

    assert_redirected_to root_path
  end

  test "unauthenticated user is redirected to sign in" do
    get admin_system_health_url

    assert_redirected_to new_session_path
  end

  # The redirect's morph reloads the frame from its old src, so an override
  # dropped on the way would leave the page and the frame in two languages.

  private
    def stub_healthy_sidekiq
      SidekiqHealth.any_instance.stubs(:healthy?).returns(true)
      SidekiqHealth.any_instance.stubs(:processes_count).returns(1)
      SidekiqHealth.any_instance.stubs(:last_heartbeat_at).returns(Time.current)
      SidekiqHealth.any_instance.stubs(:max_queue_latency).returns(0.0)
      SidekiqHealth.any_instance.stubs(:enqueued_count).returns(0)
      SidekiqHealth.any_instance.stubs(:retry_count).returns(0)
      SidekiqHealth.any_instance.stubs(:failed_count).returns(0)
      SidekiqHealth.any_instance.stubs(:processed_count).returns(42)
      SidekiqHealth.any_instance.stubs(:queue_breakdown).returns([ [ "default", 0, 0.0 ] ])
    end
end
