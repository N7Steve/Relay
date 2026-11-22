package app.relay.android.data

import java.math.BigDecimal
import java.util.Locale
import kotlinx.coroutines.runBlocking
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
        repo = RelayRepository(store, device, api) { now }
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

    @Test fun summaryCombinesAllAccountPagesAndTheBalanceSheet() = runBlocking {
        signIn()
        val account = """{"id":"%s","name":"%s","balance_cents":%d,"currency":"EUR","classification":"%s","account_type":"%s"}"""
        // Accounts and the balance sheet load concurrently: answer by path.
        route(
            "/api/v1/accounts?page=1&per_page=100" to json("""{"accounts":[${account.format("1", "Cuenta", 150000, "asset", "depository")}],"pagination":{"page":1,"per_page":100,"total_count":2,"total_pages":2}}"""),
            "/api/v1/accounts?page=2&per_page=100" to json("""{"accounts":[${account.format("2", "Tarjeta", 50000, "liability", "credit_card")}],"pagination":{"page":2,"per_page":100,"total_count":2,"total_pages":2}}"""),
            "/api/v1/balance_sheet" to json("""{"currency":"EUR","net_worth":{"amount":"1000.0","currency":"EUR","formatted":"€1,000.00"},
                "assets":{"amount":"1500.0","currency":"EUR"},"liabilities":{"amount":"500.0","currency":"EUR"}}"""),
        )
        val summary = repo.loadSummary()
        assertEquals(listOf("1", "2"), summary.accounts.map { it.id }.sorted())
        assertEquals(BigDecimal("1000.0"), summary.balanceSheet?.netWorth?.decimal)
        assertEquals(summary, store.current.summary)
    }

    @Test fun missingExchangeRatesKeepTheAccountsVisible() = runBlocking {
        signIn()
        route(
            "/api/v1/accounts?page=1&per_page=100" to json("""{"accounts":[],"pagination":{"page":1,"per_page":100,"total_count":0,"total_pages":1}}"""),
            "/api/v1/balance_sheet" to json("""{"error":"Insufficient financial data"}""", 422),
        )
        val summary = repo.loadSummary()
        assertNull(summary.balanceSheet)
        assertTrue(summary.balanceSheetError!!.contains("tipos de cambio"))
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
