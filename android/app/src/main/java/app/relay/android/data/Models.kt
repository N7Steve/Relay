package app.relay.android.data

import java.math.BigDecimal
import java.text.NumberFormat
import java.time.LocalDate
import java.util.Currency
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive

/** Cloudflare Access Service Token sent only to the configured HTTPS origin. */
@Serializable data class CloudflareAccess(val clientId: String, val clientSecret: String) {
    override fun toString() = "CloudflareAccess([redacted])"

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

@Serializable data class SavedCredentials(
    val server: String,
    val email: String,
    val password: String,
    val cloudflareAccess: CloudflareAccess? = null,
) {
    override fun toString() = "SavedCredentials(server=$server, email=$email, password=[redacted])"
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
    val savedCredentials: SavedCredentials? = null,
    val tokens: Tokens? = null,
    val user: User? = null,
    val summary: Summary? = null,
    val preferences: Preferences = Preferences(),
) {
    val signedIn get() = tokens != null && user != null
}

/** Per-device choices; cleared with the session. */
@Serializable data class Preferences(
    /** Account opened first in Movimientos; null shows every account. */
    val defaultAccountId: String? = null,
    val netWorthRange: NetWorthRange = NetWorthRange.Month,
)

enum class NetWorthRange(val label: String, val days: Long) {
    Month("1M", 30), Quarter("3M", 91), Half("6M", 182), Year("1A", 365), TwoYears("2A", 730),
}

@Serializable data class Summary(
    val accounts: List<Account>,
    val balanceSheet: BalanceSheet? = null,
    val balanceSheetError: String? = null,
    val fetchedAt: Long,
    val cashFlow: CashFlow? = null,
    val netWorthHistory: NetWorthHistory? = null,
    val netWorthRange: NetWorthRange = NetWorthRange.Month,
    /** Family setting: the day each reporting month starts (1–28). */
    val monthStartDay: Int = 1,
)

@Serializable data class CashFlow(
    /** Only in summaries cached before custom month periods; [period] replaces it. */
    val month: String? = null,
    @SerialName("as_of") val asOf: String,
    val currency: String,
    val income: String,
    val spending: String,
    @SerialName("net_savings") val netSavings: String,
    val sankey: CashFlowBreakdown,
    val period: ReportPeriod? = null,
)

@Serializable data class ReportPeriod(@SerialName("start_date") val startDate: String, @SerialName("end_date") val endDate: String)

/** `GET /cash_flow?view=sankey` for an explicit period. */
@Serializable data class CashFlowGraph(
    @SerialName("as_of") val asOf: String,
    val currency: String,
    val period: ReportPeriod,
    val sankey: SankeyTotals,
) {
    fun cashFlow() = CashFlow(
        asOf = asOf, currency = currency, income = sankey.income, spending = sankey.spending,
        netSavings = sankey.netSavings, sankey = CashFlowBreakdown(sankey.nodes, sankey.links), period = period,
    )
}

@Serializable data class SankeyTotals(
    val income: String,
    val spending: String,
    @SerialName("net_savings") val netSavings: String,
    val nodes: List<CashFlowNode>,
    val links: List<CashFlowLink>,
)

@Serializable data class FamilySettings(@SerialName("month_start_day") val monthStartDay: Int = 1)

/** First day of the reporting month containing [today], as Relay's Family#custom_month_start_for. */
fun reportingMonthStart(today: LocalDate, startDay: Int): LocalDate {
    val day = startDay.coerceIn(1, 28)
    return if (today.dayOfMonth >= day) today.withDayOfMonth(day) else today.minusMonths(1).withDayOfMonth(day)
}

/** A late start (after the 15th) names the following month, as the web dashboard does. */
fun reportingMonthName(start: LocalDate, startDay: Int): LocalDate =
    if (startDay > 15) start.plusMonths(1).withDayOfMonth(1) else start.withDayOfMonth(1)

@Serializable data class CashFlowBreakdown(val nodes: List<CashFlowNode>, val links: List<CashFlowLink>) {
    fun expenseCategories(): List<CashFlowNode> {
        val center = nodes.indexOfFirst { it.kind == "cash_flow" }
        if (center < 0) return emptyList()
        return links.filter { it.source == center }
            .mapNotNull { nodes.getOrNull(it.target)?.takeIf { node -> node.kind == "expense" && !node.boundaryTransfer } }
            .sortedByDescending { it.value.toBigDecimal() }
    }

    /**
     * [kind] is "expense" or "income"; expense flows leave the centre node, income flows enter it.
     * Money crossing the boundary of the family's finances is left out, as in the web report's tables.
     */
    fun categories(kind: String): List<FlowCategory> = sides(kind).filterNot { it.node.boundaryTransfer }

    /** Transfers to or from accounts outside the family's finances: outflows first, as the web's transfer table. */
    fun boundaryTransfers(): List<FlowCategory> = (sides("expense") + sides("income")).filter { it.node.boundaryTransfer }

    private fun sides(kind: String): List<FlowCategory> {
        val center = nodes.indexOfFirst { it.kind == "cash_flow" }
        if (center < 0) return emptyList()
        val outward = kind == "expense"
        fun next(index: Int) = if (outward) links.filter { it.source == index }.map { it.target } else links.filter { it.target == index }.map { it.source }
        return next(center).mapNotNull { root ->
            val node = nodes.getOrNull(root)?.takeIf { it.kind == kind } ?: return@mapNotNull null
            val children = next(root).mapNotNull { nodes.getOrNull(it) }.filter { it.kind == kind }.sortedByDescending { it.value.toBigDecimal() }
            FlowCategory(node, children)
        }.sortedByDescending { it.node.value.toBigDecimal() }
    }
}

/** `POST /actions/get_activity_report`: the web report's headline figures for a period. */
@Serializable data class ActivityReport(
    val currency: String,
    val period: ReportPeriod,
    val current: ActivityTotals,
    val previous: ActivityTotals,
    @SerialName("net_savings") val netSavings: Money,
    @SerialName("income_change_percent") val incomeChangePercent: String? = null,
    @SerialName("expense_change_percent") val expenseChangePercent: String? = null,
)

@Serializable data class ActivityTotals(
    val income: Money,
    val expenses: Money,
    @SerialName("investment_return") val investmentReturn: Money? = null,
)

/** `POST /actions/get_spending_trend`: cumulative spending against the previous month. */
@Serializable data class SpendingTrend(
    val currency: String,
    val period: ReportPeriod,
    @SerialName("previous_period") val previousPeriod: ReportPeriod,
    @SerialName("current_total") val currentTotal: String,
    @SerialName("comparison_total") val comparisonTotal: String,
    val delta: String,
    val current: List<SpendingPoint>,
    val previous: List<SpendingPoint>,
)

@Serializable data class SpendingPoint(val date: String, val amount: String) {
    val decimal: BigDecimal get() = amount.toBigDecimalOrNull() ?: BigDecimal.ZERO
}

@Serializable data class CashFlowNode(
    val name: String,
    val kind: String,
    val value: String,
    val color: String? = null,
    @SerialName("category_id") val categoryId: String? = null,
    /** Relay's node key, e.g. "expense_<category id>" or "expense_transfer_to_excluded". */
    val id: String? = null,
) {
    /** Relay's synthetic category for transfers to or from accounts outside the family's finances. */
    val boundaryTransfer: Boolean get() = id != null && BOUNDARY_KEYS.any(id::endsWith)

    private companion object {
        val BOUNDARY_KEYS = listOf("_transfer_to_excluded", "_transfer_from_excluded")
    }
}

/** A top-level category of one side of the cash flow, with its subcategories. */
data class FlowCategory(val node: CashFlowNode, val children: List<CashFlowNode>)
@Serializable data class CashFlowLink(val source: Int, val target: Int)
@Serializable data class NetWorthHistory(val currency: String, val points: List<NetWorthPoint>)
@Serializable data class NetWorthPoint(val date: String, val value: Money)

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
    @SerialName("logo_url") val logoUrl: String? = null,
    val capabilities: AccountCapabilities? = null,
) {
    val isLiability get() = classification == "liability"
    /** Servers that predate capabilities are treated as writable; the API still enforces access. */
    val writable get() = capabilities?.write != false && status != "disabled"
}

@Serializable data class AccountCapabilities(val read: Boolean = true, val annotate: Boolean = false, val write: Boolean = false)

@Serializable data class AccountsPage(val accounts: List<Account>, val pagination: Pagination = Pagination())

@Serializable data class AccountRef(val id: String, val name: String, @SerialName("account_type") val accountType: String? = null)
@Serializable data class CategoryRef(val id: String, val name: String, val color: String? = null, val icon: String? = null)
@Serializable data class CategoriesPage(val categories: List<CategoryOption>, val pagination: Pagination = Pagination())
@Serializable data class CategoryOption(
    val id: String,
    val name: String,
    val color: String? = null,
    val icon: String? = null,
    val parent: NamedRef? = null,
)
@Serializable data class NamedRef(
    val id: String,
    val name: String,
    @SerialName("logo_url") val logoUrl: String? = null,
    val parent: NamedRef? = null,
) {
    val label get() = parent?.let { "${it.name} / $name" } ?: name
}
@Serializable data class TransferRef(val id: String, @SerialName("other_account") val otherAccount: AccountRef? = null)
@Serializable data class TagRef(val id: String, val name: String, val color: String? = null)

/** Another family member, e.g. who owns the other side of a transfer into a shared account. */
@Serializable data class MemberRef(
    val id: String,
    val name: String,
    val initials: String? = null,
    /** Changes with the profile picture; null when the member has none. */
    @SerialName("avatar_key") val avatarKey: String? = null,
)

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
    @SerialName("editable_fields") val editableFields: List<String> = emptyList(),
    val kind: String? = null,
    @SerialName("native_operation") val nativeOperation: String? = null,
    @SerialName("shared_expense") val sharedExpense: Boolean = false,
    val excluded: Boolean = false,
    val source: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    /** Set when the other side of the transfer belongs to another member. */
    @SerialName("counterparty_owner") val counterpartyOwner: MemberRef? = null,
) {
    val isIncome get() = signedAmountCents > 0

    /** What the movement is, which decides its icon, detail and editable fields. */
    val type: MovementType get() = when {
        nativeOperation == "valuation" || kind == "investment_value_adjustment" -> MovementType.Valuation
        nativeOperation == "contribution" || kind == "investment_contribution" -> MovementType.Contribution
        nativeOperation == "withdrawal" -> MovementType.Withdrawal
        nativeOperation == "transfer" || transfer != null || kind in TRANSFER_KINDS -> MovementType.Transfer
        isIncome -> MovementType.Income
        else -> MovementType.Expense
    }

    /**
     * Whether Relay adds this movement to its category's income or spending, as the report totals do: loan payments
     * count, while transfers, contributions, valuations, managed portfolio operations and excluded movements do not.
     */
    val countsInCategoryTotals: Boolean get() = !excluded && nativeOperation == null && kind !in UNCOUNTED_KINDS

    companion object {
        val TRANSFER_KINDS = setOf("funds_movement", "cc_payment", "loan_payment", "investment_contribution", "transfer_to_excluded", "transfer_from_excluded")
        private val UNCOUNTED_KINDS = setOf("funds_movement", "one_time", "cc_payment", "investment_contribution", "investment_value_adjustment",
            "transfer_to_excluded", "transfer_from_excluded")
    }
}

enum class MovementType(val label: String) {
    Expense("Gasto"), Income("Ingreso"), Transfer("Transferencia"),
    Contribution("Aportación"), Withdrawal("Retirada"), Valuation("Valoración");

    /** Ordinary income and spending carry a category, merchant and tags. */
    val ordinary get() = this == Expense || this == Income
}

@Serializable data class TransactionsPage(val transactions: List<Transaction>, val pagination: Pagination = Pagination())

/** Minor units → localized currency text, e.g. 123456 EUR → "1.234,56 €". */
fun formatMoney(minor: Long, currency: String, locale: Locale = Locale.getDefault(), signed: Boolean = false): String {
    return formatMoney(minorToDecimal(minor, currency), currency, locale, signed)
}

fun minorToDecimal(minor: Long, currency: String): BigDecimal = BigDecimal.valueOf(minor, currencyDigits(currency))

fun currencyDigits(currency: String): Int {
    val unit = runCatching { Currency.getInstance(currency) }.getOrNull()
    return (unit?.defaultFractionDigits ?: 2).coerceAtLeast(0)
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
