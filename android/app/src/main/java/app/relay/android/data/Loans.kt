package app.relay.android.data

import java.math.BigDecimal
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Read-only loan figures from `GET /loans` and `GET /loans/{id}`. Every figure is computed by
 * Relay's loan engine (schedule, rate revisions, posted interest); the app only presents them.
 */
@Serializable data class LoansPage(@SerialName("as_of") val asOf: String? = null, val loans: List<LoanListItem> = emptyList())

@Serializable data class LoanListItem(val account: Account, val summary: LoanSummary)

@Serializable data class LoanSummary(
    val currency: String,
    @SerialName("current_debt") val currentDebt: Money,
    @SerialName("original_principal") val originalPrincipal: Money,
    /** Share of the original principal repaid (0–1), measured against the account balance. */
    @SerialName("repaid_ratio") val repaidRatio: Double? = null,
    /** Only loans that post their interest know how the instalments split. */
    @SerialName("principal_repaid") val principalRepaid: Money? = null,
    @SerialName("interest_paid") val interestPaid: Money? = null,
    /** Annual percentage as a decimal string, e.g. "1.5". */
    @SerialName("current_rate") val currentRate: String? = null,
    @SerialName("rate_type") val rateType: String? = null,
    @SerialName("structured_rate") val structuredRate: Boolean = false,
    @SerialName("interest_tracking") val interestTracking: Boolean = false,
    /** The next scheduled instalment. */
    val payment: Money? = null,
    @SerialName("next_payment_date") val nextPaymentDate: String? = null,
    @SerialName("next_payment_number") val nextPaymentNumber: Int? = null,
    @SerialName("term_months") val termMonths: Int? = null,
    @SerialName("remaining_months") val remainingMonths: Int? = null,
    @SerialName("start_date") val startDate: String? = null,
    @SerialName("payoff_date") val payoffDate: String? = null,
    @SerialName("total_cost") val totalCost: Money? = null,
)

@Serializable data class LoanDetail(
    @SerialName("as_of") val asOf: String? = null,
    val account: Account,
    val summary: LoanSummary,
    @SerialName("current_instalment") val currentInstalment: LoanInstalment? = null,
    val rate: LoanRate = LoanRate(),
    val schedule: LoanSchedule? = null,
)

@Serializable data class LoanInstalment(
    val number: Int,
    val date: String,
    val total: Money,
    val principal: Money,
    val interest: Money,
    val insurance: Money? = null,
    val ratios: LoanRatios = LoanRatios(),
)

@Serializable data class LoanRatios(val principal: Double = 0.0, val interest: Double = 0.0, val insurance: Double = 0.0)

@Serializable data class LoanRate(
    val structured: Boolean = false,
    @SerialName("current_rate") val currentRate: String? = null,
    val current: LoanRevision? = null,
    @SerialName("next_revision") val nextRevision: LoanRevision? = null,
    val revisions: List<LoanRevision> = emptyList(),
    val periods: List<LoanRatePeriod> = emptyList(),
    val bonuses: List<LoanBonus> = emptyList(),
)

@Serializable data class LoanRevision(
    @SerialName("effective_on") val effectiveOn: String,
    val rate: String,
    @SerialName("rate_kind") val rateKind: String = "fixed",
    /** projected (ahead), pending (due, not recorded yet), calculated or confirmed. */
    val status: String = "calculated",
    @SerialName("base_rate") val baseRate: String? = null,
    @SerialName("reference_index") val referenceIndex: String? = null,
    @SerialName("reference_index_name") val referenceIndexName: String? = null,
    @SerialName("index_month") val indexMonth: String? = null,
    @SerialName("index_value") val indexValue: String? = null,
    val spread: String? = null,
    @SerialName("bonus_points") val bonusPoints: String = "0",
    /** Server-side wording in the server's locale; the app writes its own in Spanish. */
    val composition: String? = null,
    /** Next revision only: the first instalment sized at the new rate. */
    @SerialName("new_payment") val newPayment: Money? = null,
    @SerialName("new_payment_date") val newPaymentDate: String? = null,
) {
    val variable get() = rateKind == "variable"

    /** "Euríbor 12M 3,239 % (oct 2026) + diferencial 1,80 % − bonificaciones 1,20 %", as the web Rates tab. */
    fun compositionText(): String = buildList {
        if (variable) {
            val month = indexMonth?.let { runCatching { LocalDate.parse(it).format(loanMonthYear) }.getOrNull() }
            add(listOfNotNull(indexName(referenceIndex, referenceIndexName), formatRate(indexValue), month?.let { "($it)" }).joinToString(" "))
            add("+ diferencial ${formatRate(spread)}")
        } else {
            add("Fijo ${formatRate(baseRate)}")
        }
        if ((bonusPoints.toBigDecimalOrNull() ?: BigDecimal.ZERO).signum() > 0) add("− bonificaciones ${formatRate(bonusPoints)}")
    }.joinToString(" ")

    val statusLabel get() = when (status) {
        "projected" -> "Prevista"
        "pending" -> "Pendiente"
        "confirmed" -> "Confirmada"
        else -> "Calculada"
    }
}

@Serializable data class LoanRatePeriod(
    @SerialName("starts_on") val startsOn: String,
    @SerialName("rate_kind") val rateKind: String,
    @SerialName("base_rate") val baseRate: String? = null,
    @SerialName("reference_index") val referenceIndex: String? = null,
    @SerialName("reference_index_name") val referenceIndexName: String? = null,
    val spread: String? = null,
    @SerialName("floor_rate") val floorRate: String? = null,
    @SerialName("review_interval_months") val reviewIntervalMonths: Int = 12,
    @SerialName("applies_bonuses") val appliesBonuses: Boolean = true,
    @SerialName("lender_name") val lenderName: String? = null,
) {
    /** "Fijo 2,70 %" or "Euríbor 12M + 1,80 %", with how often it is revised. */
    fun termsText(): String {
        val terms = if (rateKind == "variable") "${indexName(referenceIndex, referenceIndexName) ?: "Índice"} + ${formatRate(spread)}"
        else "Fijo ${formatRate(baseRate)}"
        val review = if (reviewIntervalMonths == 12) "revisión anual" else "revisión cada $reviewIntervalMonths meses"
        return listOfNotNull(terms, review, lenderName?.takeIf { it.isNotBlank() }).joinToString(" · ")
    }
}

@Serializable data class LoanBonus(
    val name: String,
    val kind: String? = null,
    val points: String,
    val active: Boolean = true,
    @SerialName("annual_cost") val annualCost: Money? = null,
)

@Serializable data class LoanSchedule(
    val currency: String,
    @SerialName("re_amortising") val reAmortising: Boolean = false,
    @SerialName("opening_payment") val openingPayment: Money? = null,
    @SerialName("total_interest") val totalInterest: Money? = null,
    @SerialName("total_paid") val totalPaid: Money? = null,
    @SerialName("payoff_date") val payoffDate: String? = null,
    @SerialName("projected_payoff_date") val projectedPayoffDate: String? = null,
    val payments: List<LoanPayment> = emptyList(),
) {
    /** Instalments still ahead, the next one first. */
    val upcoming get() = payments.filterNot { it.past }
    /** Instalments already due, the latest first. */
    val paid get() = payments.filter { it.past }.asReversed()
}

/** One instalment of the schedule; amounts are decimal strings in the schedule currency. */
@Serializable data class LoanPayment(
    val number: Int,
    val date: String,
    val payment: String,
    val principal: String,
    val interest: String,
    val prepayment: String = "0",
    @SerialName("ending_balance") val endingBalance: String,
    val past: Boolean = false,
)

fun String?.decimalOrZero(): BigDecimal = this?.toBigDecimalOrNull() ?: BigDecimal.ZERO

private val spain = Locale.forLanguageTag("es-ES")
private val loanMonthYear = DateTimeFormatter.ofPattern("MMM yyyy", spain)

/** A rate as Spanish lenders quote it: "1,50 %", "3,839 %". */
fun formatRate(value: String?, locale: Locale = spain): String {
    val rate = value?.toBigDecimalOrNull() ?: return "—"
    val format = NumberFormat.getNumberInstance(locale).apply { minimumFractionDigits = 2; maximumFractionDigits = 3 }
    return "${format.format(rate)} %"
}

/** Spanish name of a reference index; the server's name (in its locale) or the key otherwise. */
fun indexName(key: String?, serverName: String? = null): String? = when (key) {
    null -> serverName
    "euribor_12m" -> "Euríbor 12M"
    else -> serverName ?: key
}

/** Loan subtypes as Relay names them in Spanish. */
fun loanSubtypeName(subtype: String?): String = when (subtype) {
    "mortgage" -> "Hipoteca"
    "student" -> "Préstamo de estudios"
    "auto" -> "Préstamo de coche"
    "home_equity" -> "Préstamo con garantía hipotecaria"
    "line_of_credit" -> "Línea de crédito"
    "business" -> "Préstamo empresarial"
    else -> "Préstamo"
}

/** "30 años", "18 meses", "2 años y 3 meses". */
fun formatTerm(months: Int?): String? {
    if (months == null || months < 0) return null
    val years = months / 12
    val rest = months % 12
    fun plural(count: Int, one: String, many: String) = "$count ${if (count == 1) one else many}"
    return when {
        years == 0 -> plural(rest, "mes", "meses")
        rest == 0 -> plural(years, "año", "años")
        else -> "${plural(years, "año", "años")} y ${plural(rest, "mes", "meses")}"
    }
}
