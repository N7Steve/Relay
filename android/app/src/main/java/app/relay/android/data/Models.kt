package app.relay.android.data

import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive

/** Cloudflare Access Service Token sent only to the configured HTTPS origin. */
@Serializable data class CloudflareAccess(val clientId: String, val clientSecret: String) {
    companion object {
        fun fromInput(clientId: String, clientSecret: String): CloudflareAccess? {
            val id = clientId.trim()
            val secret = clientSecret.trim()
            if (id.isEmpty() && secret.isEmpty()) return null
            require(id.isNotEmpty() && secret.isNotEmpty()) { "Completa el Client ID y el Client Secret de Cloudflare Access, o deja ambos vacíos." }
            require(listOf(id, secret).all { value -> value.length <= 512 && value.all { it in '!'..'~' } }) {
                "El Service Token de Cloudflare Access contiene caracteres no válidos."
            }
            return CloudflareAccess(id, secret)
        }
    }
}

@Serializable data class Tokens(val accessToken: String, val refreshToken: String, val expiresAt: Long)

@Serializable data class User(
    val id: String,
    val email: String,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
) {
    val displayName get() = listOfNotNull(firstName, lastName).joinToString(" ").trim().ifEmpty { email }
}

/** Everything the app persists, encrypted as one document. */
@Serializable data class DiskState(
    val server: String = "",
    val deviceId: String = "",
    val cloudflareAccess: CloudflareAccess? = null,
    val tokens: Tokens? = null,
    val user: User? = null,
    val summary: Summary? = null,
) {
    val signedIn get() = tokens != null && user != null
}

@Serializable data class Summary(
    val accounts: List<Account>,
    val balanceSheet: BalanceSheet? = null,
    val balanceSheetError: String? = null,
    val fetchedAt: Long,
)

@Serializable data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Long = 0,
    @SerialName("created_at") val createdAt: Long = 0,
    val user: User? = null,
) {
    fun tokens(now: Long = System.currentTimeMillis()): Tokens {
        val issued = if (createdAt > 0) createdAt * 1000 else now
        val lifetime = if (expiresIn > 0) expiresIn * 1000 else 30L * 24 * 3600 * 1000
        return Tokens(accessToken, refreshToken, issued + lifetime)
    }
}

@Serializable data class Money(val amount: JsonPrimitive, val currency: String, val formatted: String? = null) {
    val decimal: BigDecimal get() = amount.content.toBigDecimalOrNull() ?: BigDecimal.ZERO
}

@Serializable data class BalanceSheet(
    val currency: String,
    @SerialName("net_worth") val netWorth: Money,
    val assets: Money,
    val liabilities: Money,
)

@Serializable data class Pagination(
    val page: Int = 1,
    @SerialName("per_page") val perPage: Int = 0,
    @SerialName("total_count") val totalCount: Int = 0,
    @SerialName("total_pages") val totalPages: Int = 0,
)

@Serializable data class Account(
    val id: String,
    val name: String,
    @SerialName("balance_cents") val balanceCents: Long = 0,
    val currency: String,
    val classification: String? = null,
    @SerialName("account_type") val accountType: String? = null,
    val subtype: String? = null,
    val status: String? = null,
    @SerialName("institution_name") val institutionName: String? = null,
) {
    val isLiability get() = classification == "liability"
}

@Serializable data class AccountsPage(val accounts: List<Account>, val pagination: Pagination = Pagination())

@Serializable data class AccountRef(val id: String, val name: String, @SerialName("account_type") val accountType: String? = null)
@Serializable data class CategoryRef(val id: String, val name: String, val color: String? = null, val icon: String? = null)
@Serializable data class NamedRef(val id: String, val name: String)
@Serializable data class TransferRef(val id: String, @SerialName("other_account") val otherAccount: AccountRef? = null)
@Serializable data class TagRef(val id: String, val name: String, val color: String? = null)

@Serializable data class Transaction(
    val id: String,
    val date: String,
    val name: String = "",
    @SerialName("amount_cents") val amountCents: Long = 0,
    @SerialName("signed_amount_cents") val signedAmountCents: Long = 0,
    val currency: String,
    val classification: String? = null,
    val notes: String? = null,
    val account: AccountRef? = null,
    val category: CategoryRef? = null,
    val merchant: NamedRef? = null,
    val transfer: TransferRef? = null,
    val tags: List<TagRef> = emptyList(),
) {
    val isIncome get() = signedAmountCents > 0
}

@Serializable data class TransactionsPage(val transactions: List<Transaction>, val pagination: Pagination = Pagination())

/** Minor units → localized currency text, e.g. 123456 EUR → "1.234,56 €". */
fun formatMoney(minor: Long, currency: String, locale: Locale = Locale.getDefault(), signed: Boolean = false): String {
    val unit = runCatching { Currency.getInstance(currency) }.getOrNull()
    val digits = (unit?.defaultFractionDigits ?: 2).coerceAtLeast(0)
    return formatMoney(BigDecimal.valueOf(minor, digits), currency, locale, signed)
}

fun formatMoney(amount: BigDecimal, currency: String, locale: Locale = Locale.getDefault(), signed: Boolean = false): String {
    val unit = runCatching { Currency.getInstance(currency) }.getOrNull()
    val digits = (unit?.defaultFractionDigits ?: 2).coerceAtLeast(0)
    val format = NumberFormat.getCurrencyInstance(locale).apply {
        unit?.let { this.currency = it }
        minimumFractionDigits = digits
        maximumFractionDigits = digits
    }
    val text = format.format(amount.abs())
    return when {
        amount.signum() < 0 -> "−$text"
        signed && amount.signum() > 0 -> "+$text"
        else -> text
    }
}
