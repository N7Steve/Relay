package app.relay.android.data

import java.math.BigDecimal
import java.time.LocalDate
import java.util.Locale
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RelayRepositoryTest {
    private lateinit var server: MockWebServer
    private lateinit var api: RelayApi
    private lateinit var store: MemoryStore
    private lateinit var repo: RelayRepository
    private var now = 1_700_000_000_000L
    private val device = DeviceInfo("Pixel Test", "15", "0.1.1")

    class MemoryStore(var current: DiskState = DiskState()) : StateStore {
        override fun read() = current
        override fun write(state: DiskState) { current = state }
    }

    @Before fun setup() = runBlocking {
        val certificate = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        server = MockWebServer().apply { useHttps(serverCertificates.sslSocketFactory(), false); start() }
        api = RelayApi(RelayApi.defaultClient().newBuilder().sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager).build())
        store = MemoryStore()
        repo = RelayRepository(store, device, api, today = { LocalDate.parse("2026-11-22") }) { now }
        repo.initialize()
    }

    @After fun cleanup() { server.shutdown() }

    private fun origin() = server.url("/").newBuilder().host("localhost").build().toString()
    private fun json(body: String, code: Int = 200) = MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body)
    private fun tokens(access: String, refresh: String, expiresIn: Long = 2_592_000) =
        """{"access_token":"$access","refresh_token":"$refresh","token_type":"Bearer","expires_in":$expiresIn,"created_at":${now / 1000},
           "user":{"id":"u1","email":"steve@example.com","first_name":"Steve","last_name":null}}"""

    private fun route(vararg responses: Pair<String, MockResponse>) {
        val table = mapOf(*responses)
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest) = table[request.path] ?: MockResponse().setResponseCode(404)
        }
    }

    private suspend fun signIn(access: String = "a1", refresh: String = "r1", expiresIn: Long = 2_592_000) {
        server.enqueue(json(tokens(access, refresh, expiresIn)))
        repo.login(origin(), "steve@example.com", "secret-password", "", "", "")
        server.takeRequest()
    }

    @Test fun loginRegistersTheDeviceAndNeverStoresThePassword() = runBlocking {
        server.enqueue(json(tokens("a1", "r1")))
        repo.login(origin(), " steve@example.com ", "secret-password", "", "", "")
        val request = server.takeRequest()
        assertEquals("/api/v1/auth/login", request.path)
        val body = api.json.parseToJsonElement(request.body.readUtf8()).jsonObject
        assertEquals("steve@example.com", body["email"]!!.jsonPrimitive.content)
        val deviceJson = body["device"]!!.jsonObject
        assertEquals("android", deviceJson["device_type"]!!.jsonPrimitive.content)
        assertEquals(store.current.deviceId, deviceJson["device_id"]!!.jsonPrimitive.content)
        assertNull(body["otp_code"])
        assertNull(request.getHeader("CF-Access-Client-Id"))
        assertTrue(store.current.signedIn)
        assertEquals("Steve", store.current.user?.displayName)
        assertFalse(api.json.encodeToString(DiskState.serializer(), store.current).contains("secret-password"))
    }

    @Test fun mfaChallengeIsReportedAndTheCodeIsSentOnRetry() = runBlocking {
        server.enqueue(json("""{"error":"Two-factor authentication required","mfa_required":true}""", 401))
        val error = assertThrows(ApiException::class.java) {
            runBlocking { repo.login(origin(), "steve@example.com", "secret", "", "", "") }
        }
        assertTrue(error.mfaRequired)
        server.takeRequest()
        server.enqueue(json(tokens("a1", "r1")))
        repo.login(origin(), "steve@example.com", "secret", "123 456", "", "")
        val body = api.json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject
        assertEquals("123456", body["otp_code"]!!.jsonPrimitive.content)
    }

    @Test fun serviceTokenIsSentOnEveryRequestIncludingRefresh() = runBlocking {
        server.enqueue(json(tokens("a1", "r1", expiresIn = 30)))
        repo.login(origin(), "steve@example.com", "secret", "", " service-id ", " service-secret ")
        assertEquals("service-id", server.takeRequest().getHeader("CF-Access-Client-Id"))
        assertEquals(CloudflareAccess("service-id", "service-secret"), store.current.cloudflareAccess)

        server.enqueue(json(tokens("a2", "r2")))
        server.enqueue(json("""{"accounts":[],"pagination":{"page":1,"per_page":100,"total_count":0,"total_pages":0}}"""))
        repo.authorized("/accounts")
        val refresh = server.takeRequest()
        assertEquals("/api/v1/auth/refresh", refresh.path)
        assertEquals("service-secret", refresh.getHeader("CF-Access-Client-Secret"))
        val accounts = server.takeRequest()
        assertEquals("Bearer a2", accounts.getHeader("Authorization"))
        assertEquals("service-id", accounts.getHeader("CF-Access-Client-Id"))
    }

    @Test fun incompleteServiceTokenIsRejectedBeforeAnyRequest() {
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { repo.login(origin(), "steve@example.com", "secret", "", "only-id", "") }
        }
        assertEquals(0, server.requestCount)
    }

    @Test fun rejectedAccessTokenIsRefreshedOnceAndRetried() = runBlocking {
        signIn()
        server.enqueue(json("""{"error":"unauthorized"}""", 401))
        server.enqueue(json(tokens("a2", "r2")))
        server.enqueue(json("""{"transactions":[],"pagination":{"page":1,"per_page":40,"total_count":0,"total_pages":0}}"""))
        repo.transactions(1)
        assertEquals("Bearer a1", server.takeRequest().getHeader("Authorization"))
        assertEquals("/api/v1/auth/refresh", server.takeRequest().path)
        assertEquals("Bearer a2", server.takeRequest().getHeader("Authorization"))
        assertEquals("r2", store.current.tokens?.refreshToken)
    }

    @Test fun revokedRefreshTokenExpiresTheSessionButKeepsTheServer() = runBlocking {
        server.enqueue(json(tokens("a1", "r1")))
        repo.login(origin(), "steve@example.com", "secret", "", "id", "secret-value")
        server.takeRequest()
        server.enqueue(json("""{"error":"unauthorized"}""", 401))
        server.enqueue(json("""{"error":"Invalid refresh token"}""", 401))
        assertThrows(SessionExpiredException::class.java) { runBlocking { repo.authorized("/accounts") } }
        assertFalse(store.current.signedIn)
        assertEquals(origin(), store.current.server)
        assertEquals("id", store.current.cloudflareAccess?.clientId)
        assertNull(store.current.summary)
    }

    @Test fun redirectsAreNeverFollowed() = runBlocking {
        signIn()
        server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "https://team.cloudflareaccess.com/cdn-cgi/access/login"))
        val error = assertThrows(ApiException::class.java) { runBlocking { repo.authorized("/accounts") } }
        assertTrue(error.message!!.contains("Cloudflare Access"))
        assertEquals(2, server.requestCount)
        assertTrue(store.current.signedIn)
    }

    @Test fun summaryCombinesPaginatedAccountsWithTheBalanceSheetAndReports() = runBlocking {
        signIn()
        val account = """{"id":"%s","name":"%s","balance_cents":%d,"currency":"EUR","classification":"%s","account_type":"%s"}"""
        route(
            "/api/v1/accounts?page=1&per_page=100&include_disabled=true" to json("""{"accounts":[${account.format("1", "Cuenta", 150000, "asset", "depository")}],"pagination":{"page":1,"per_page":100,"total_count":2,"total_pages":2}}"""),
            "/api/v1/accounts?page=2&per_page=100&include_disabled=true" to json("""{"accounts":[${account.format("2", "Tarjeta", 50000, "liability", "credit_card")}],"pagination":{"page":2,"per_page":100,"total_count":2,"total_pages":2}}"""),
            "/api/v1/balance_sheet" to json("""{"currency":"EUR","net_worth":{"amount":"1000.0","currency":"EUR","formatted":"€1,000.00"},
                "assets":{"amount":"1500.0","currency":"EUR"},"liabilities":{"amount":"500.0","currency":"EUR"}}"""),
            "/api/v1/family_settings" to json("""{"month_start_day":25}"""),
            "/api/v1/cash_flow?view=sankey&start_date=2026-10-25&end_date=2026-11-22" to json("""{"as_of":"2026-11-22","currency":"EUR",
                "period":{"start_date":"2026-10-25","end_date":"2026-11-22"},
                "sankey":{"income":"150","spending":"30","net_savings":"120","nodes":[
                  {"name":"Cash Flow","kind":"cash_flow","value":"150"},
                  {"name":"Alimentación","kind":"expense","value":"30","color":"#ef4444"},
                  {"name":"Supermercado","kind":"expense","value":"20"},
                  {"name":"Surplus","kind":"surplus","value":"120"}
                ],"links":[{"source":0,"target":1},{"source":1,"target":2},{"source":0,"target":3}]}}"""),
            "/api/v1/actions/get_net_worth_series" to json("""{"currency":"EUR","points":[
                {"date":"2026-11-22","value":{"amount":"1000.0","currency":"EUR"}}]}"""),
        )
        val summary = repo.loadSummary()
        assertEquals(listOf("1", "2"), summary.accounts.map { it.id }.sorted())
        assertEquals(BigDecimal("1000.0"), summary.balanceSheet?.netWorth?.decimal)
        assertEquals(BigDecimal("1000.0"), summary.netWorthHistory?.points?.single()?.value?.decimal)
        assertEquals(listOf("Alimentación"), summary.cashFlow?.sankey?.expenseCategories()?.map { it.name })
        assertEquals("#ef4444", summary.cashFlow?.sankey?.expenseCategories()?.single()?.color)
        assertEquals("150", summary.cashFlow?.income)
        assertEquals("2026-10-25", summary.cashFlow?.period?.startDate)
        assertEquals(25, summary.monthStartDay)
        val historyRequest = List(6) { server.takeRequest() }.single { it.path == "/api/v1/actions/get_net_worth_series" }
        assertEquals("POST", historyRequest.method)
        val period = api.json.parseToJsonElement(historyRequest.body.readUtf8()).jsonObject["arguments"]!!.jsonObject
        assertEquals("2026-10-24", period["start_date"]!!.jsonPrimitive.content)
        assertEquals("2026-11-22", period["end_date"]!!.jsonPrimitive.content)
        assertEquals(summary, store.current.summary)
    }

    @Test fun netWorthRangeIsRememberedAndRequestedForItsSpan() = runBlocking {
        signIn()
        route("/api/v1/actions/get_net_worth_series" to json("""{"currency":"EUR","points":[]}"""))
        repo.loadNetWorth(NetWorthRange.Year)
        val period = api.json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject["arguments"]!!.jsonObject
        assertEquals("2025-11-23", period["start_date"]!!.jsonPrimitive.content)
        assertEquals(NetWorthRange.Year, store.current.preferences.netWorthRange)
    }

    @Test fun reportingMonthsFollowTheFamilyStartDay() {
        assertEquals(LocalDate.parse("2026-11-01"), reportingMonthStart(LocalDate.parse("2026-11-22"), 1))
        assertEquals(LocalDate.parse("2026-10-25"), reportingMonthStart(LocalDate.parse("2026-11-22"), 25))
        assertEquals(LocalDate.parse("2026-11-10"), reportingMonthStart(LocalDate.parse("2026-11-22"), 10))
        assertEquals(LocalDate.parse("2026-11-01"), reportingMonthName(LocalDate.parse("2026-10-25"), 25))
        assertEquals(LocalDate.parse("2026-11-01"), reportingMonthName(LocalDate.parse("2026-11-10"), 10))
    }

    @Test fun storedLogosAreDownloadedWithTheSessionToken() = runBlocking {
        signIn()
        route(
            "/api/v1/accounts/a1/logo" to MockResponse().setHeader("Content-Type", "image/webp").setBody("logo"),
        )
        assertEquals("logo", repo.download("/accounts/a1/logo", 1024)?.decodeToString())
        assertEquals("Bearer a1", server.takeRequest().getHeader("Authorization"))
        assertNull(repo.download("/merchants/m1/logo", 1024))
        assertNull(repo.download("/accounts/a1/logo", 2))
    }

    @Test fun cashFlowCategoriesKeepSubcategoriesOnBothSides() {
        val breakdown = api.json.decodeFromString<CashFlowBreakdown>("""{"nodes":[
            {"name":"Nómina","kind":"income","value":"2000","category_id":"c-in"},
            {"name":"Cash Flow","kind":"cash_flow","value":"2000"},
            {"name":"Hogar","kind":"expense","value":"900","category_id":"c-home","color":"#22c55e"},
            {"name":"Alquiler","kind":"expense","value":"700","category_id":"c-rent"},
            {"name":"Ocio","kind":"expense","value":"100","category_id":"c-fun"},
            {"name":"Surplus","kind":"surplus","value":"1000"}
          ],"links":[{"source":0,"target":1},{"source":1,"target":2},{"source":2,"target":3},{"source":1,"target":4},{"source":1,"target":5}]}""")
        val expenses = breakdown.categories("expense")
        assertEquals(listOf("Hogar", "Ocio"), expenses.map { it.node.name })
        assertEquals(listOf("c-rent"), expenses.first().children.map { it.categoryId })
        assertEquals(listOf("Nómina"), breakdown.categories("income").map { it.node.name })
    }

    @Test fun activityReportAndCategoryMovementsUseTheReportPeriod() = runBlocking {
        signIn()
        route(
            "/api/v1/actions/get_activity_report" to json("""{"currency":"EUR","period":{"start_date":"2026-10-25","end_date":"2026-11-24"},
                "current":{"income":{"amount":"2000.0","currency":"EUR"},"expenses":{"amount":"1500.0","currency":"EUR"},
                  "investment_return":{"amount":"0.0","currency":"EUR"}},
                "previous":{"income":{"amount":"1800.0","currency":"EUR"},"expenses":{"amount":"1600.0","currency":"EUR"}},
                "net_savings":{"amount":"500.0","currency":"EUR"},"income_change_percent":"11.1","expense_change_percent":"-6.3"}"""),
            "/api/v1/transactions?page=1&per_page=100&category_id=c1&start_date=2026-10-25&end_date=2026-11-24" to json(
                """{"transactions":[{"id":"t1","date":"2026-11-02","currency":"EUR"}]}"""),
            "/api/v1/transactions?page=1&per_page=100&category_id=c2&start_date=2026-10-25&end_date=2026-11-24" to json(
                """{"transactions":[{"id":"t2","date":"2026-11-20","currency":"EUR"},{"id":"t1","date":"2026-11-02","currency":"EUR"}]}"""),
        )
        val start = LocalDate.parse("2026-10-25")
        val end = LocalDate.parse("2026-11-24")
        val report = repo.activityReport(start, end)
        assertEquals(BigDecimal("500.0"), report.netSavings.decimal)
        assertEquals("-6.3", report.expenseChangePercent)
        val period = api.json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject["arguments"]!!.jsonObject
        assertEquals("2026-10-25", period["start_date"]!!.jsonPrimitive.content)
        assertEquals(listOf("t2", "t1"), repo.categoryTransactions(listOf("c1", "c2"), start, end).map { it.id })
    }

    @Test fun missingExchangeRatesKeepTheAccountsVisible() = runBlocking {
        signIn()
        route(
            "/api/v1/accounts?page=1&per_page=100&include_disabled=true" to json("""{"accounts":[],"pagination":{"page":1,"per_page":100,"total_count":0,"total_pages":1}}"""),
            "/api/v1/balance_sheet" to json("""{"error":"Insufficient financial data"}""", 422),
        )
        val summary = repo.loadSummary()
        assertNull(summary.balanceSheet)
        assertTrue(summary.balanceSheetError!!.contains("tipos de cambio"))
    }

    @Test fun transactionPatchKeepsExplicitNullsAndReadsTheMerchantLogo() = runBlocking {
        signIn()
        server.enqueue(json("""{"id":"t1","date":"2026-11-22","name":"Updated","currency":"EUR",
            "merchant":{"id":"m1","name":"Comercio","logo_url":"https://logos.example.com/merchant.png"},"editable_fields":["category_id"]}"""))
        val updated = repo.updateTransaction("t1", fields("category_id" to JsonNull, "amount" to value("-12.34")))
        val request = server.takeRequest()
        assertEquals("PATCH", request.method)
        assertEquals("/api/v1/transactions/t1", request.path)
        assertEquals("Bearer a1", request.getHeader("Authorization"))
        val changes = api.json.parseToJsonElement(request.body.readUtf8()).jsonObject["transaction"]!!.jsonObject
        assertEquals(JsonNull, changes["category_id"])
        assertEquals("-12.34", changes["amount"]!!.jsonPrimitive.content)
        assertEquals("https://logos.example.com/merchant.png", updated.merchant?.logoUrl)
        assertEquals(listOf("category_id"), updated.editableFields)
    }

    @Test fun spendingTrendAndNewMovementsUseTheirActions() = runBlocking {
        signIn()
        route(
            "/api/v1/actions/get_spending_trend" to json("""{"currency":"EUR","period":{"start_date":"2026-11-01","end_date":"2026-11-02"},
                "previous_period":{"start_date":"2026-10-01","end_date":"2026-10-31"},"current_total":"30.0","comparison_total":"10.0",
                "delta":"20.0","current":[{"date":"2026-11-01","amount":"5.0"},{"date":"2026-11-02","amount":"30.0"}],
                "previous":[{"date":"2026-10-01","amount":"0.0"},{"date":"2026-10-02","amount":"10.0"}]}"""),
            "/api/v1/transactions" to json("""{"id":"t9","date":"2026-11-22","currency":"EUR","signed_amount_cents":-1250,
                "kind":"standard","shared_expense":true,"editable_fields":["notes","shared_expense"]}""", 201),
        )
        val trend = repo.spendingTrend(LocalDate.parse("2026-11-01"), LocalDate.parse("2026-11-02"))
        assertEquals(BigDecimal("30.0"), trend.current.last().decimal)
        assertEquals("2026-10-01", trend.previousPeriod.startDate)
        val trendRequest = server.takeRequest()
        assertEquals("POST", trendRequest.method)
        assertEquals("2026-11-01", api.json.parseToJsonElement(trendRequest.body.readUtf8()).jsonObject["arguments"]!!
            .jsonObject["start_date"]!!.jsonPrimitive.content)

        val created = repo.createTransaction(fields("account_id" to value("a1"), "amount" to value("12.50"), "nature" to value("expense"),
            "external_id" to value("draft-1"), "source" to value("relay-android")))
        assertTrue(created.sharedExpense)
        assertEquals(MovementType.Expense, created.type)
        val body = api.json.parseToJsonElement(server.takeRequest().body.readUtf8()).jsonObject["transaction"]!!.jsonObject
        assertEquals("draft-1", body["external_id"]!!.jsonPrimitive.content)
        assertEquals("expense", body["nature"]!!.jsonPrimitive.content)
    }

    @Test fun movementTypeFollowsKindAndNativeOperation() {
        fun movement(kind: String?, native: String? = null, cents: Long = -100, transfer: TransferRef? = null) =
            Transaction(id = "t", date = "2026-11-22", currency = "EUR", signedAmountCents = cents, kind = kind, nativeOperation = native, transfer = transfer)
        assertEquals(MovementType.Valuation, movement("investment_value_adjustment", "valuation", cents = 500).type)
        assertEquals(MovementType.Contribution, movement("investment_contribution").type)
        assertEquals(MovementType.Withdrawal, movement("funds_movement", "withdrawal").type)
        assertEquals(MovementType.Transfer, movement("funds_movement", transfer = TransferRef("x")).type)
        assertEquals(MovementType.Income, movement("standard", cents = 100).type)
        assertEquals(MovementType.Expense, movement("standard").type)
        assertEquals(MovementType.Expense, movement(null).type)
    }

    @Test fun logoutRevokesOnTheServerAndForgetsTokens() = runBlocking {
        signIn()
        server.enqueue(MockResponse().setResponseCode(204))
        repo.logout()
        val request = server.takeRequest()
        assertEquals("/api/v1/auth/logout", request.path)
        assertTrue(request.body.readUtf8().contains("\"refresh_token\":\"r1\""))
        assertFalse(store.current.signedIn)
        assertNull(store.current.cloudflareAccess)
    }

    @Test fun rememberedCredentialsSurviveExpiryAndLogoutButAreClearedByForget() = runBlocking {
        server.enqueue(json(tokens("a1", "r1")))
        repo.login(origin(), " steve@example.com ", "saved-pass", "", " cf-id ", " cf-secret ", rememberCredentials = true)
        server.takeRequest()
        val expected = SavedCredentials(origin(), "steve@example.com", "saved-pass", CloudflareAccess("cf-id", "cf-secret"))
        assertEquals(expected, store.current.savedCredentials)
        assertFalse(expected.toString().contains("saved-pass"))

        // Refresh rejection expires session while preserving savedCredentials and Service Token.
        server.enqueue(json("""{"error":"unauthorized"}""", 401))
        server.enqueue(json("""{"error":"Invalid refresh token"}""", 401))
        assertThrows(SessionExpiredException::class.java) { runBlocking { repo.authorized("/accounts") } }
        assertFalse(store.current.signedIn)
        assertEquals(expected, store.current.savedCredentials)
        assertEquals(CloudflareAccess("cf-id", "cf-secret"), store.current.cloudflareAccess)

        // Explicit logout keeps savedCredentials for quick re-entry.
        server.enqueue(json(tokens("a2", "r2")))
        repo.login(origin(), "steve@example.com", "saved-pass", "", "cf-id", "cf-secret", rememberCredentials = true)
        server.takeRequest()
        server.enqueue(MockResponse().setResponseCode(204))
        repo.logout()
        assertFalse(store.current.signedIn)
        assertNull(store.current.cloudflareAccess)
        assertEquals(expected, store.current.savedCredentials)

        // Forget locally wipes savedCredentials completely.
        repo.forget()
        assertNull(store.current.savedCredentials)
        assertNull(store.current.cloudflareAccess)
    }

    @Test fun serverAddressMustBeABareHttpsOrigin() {
        assertEquals("https://relay.example.com/", serverUrl("relay.example.com").toString())
        assertThrows(IllegalArgumentException::class.java) { serverUrl("http://relay.example.com") }
        assertThrows(IllegalArgumentException::class.java) { serverUrl("https://relay.example.com/api/v1") }
        assertThrows(IllegalArgumentException::class.java) { serverUrl("https://user:pass@relay.example.com") }
    }

    @Test fun moneyIsFormattedFromMinorUnits() {
        val spain = Locale.forLanguageTag("es-ES")
        assertEquals("123.456,78 €", formatMoney(12345678, "EUR", spain).replace(' ', ' '))
        assertEquals("−12,00 €", formatMoney(-1200, "EUR", spain).replace(' ', ' '))
        assertEquals("+5,00 €", formatMoney(500, "EUR", spain, signed = true).replace(' ', ' '))
    }
}
