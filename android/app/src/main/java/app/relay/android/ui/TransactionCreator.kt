package app.relay.android.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.relay.android.data.Account
import app.relay.android.data.NamedRef
import app.relay.android.data.TagRef
import app.relay.android.data.currencyDigits
import app.relay.android.data.formatMoney
import java.math.BigDecimal
import java.time.LocalDate
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Day-to-day accounts the user may write to, current accounts first. */
internal fun creatableAccounts(accounts: List<Account>): List<Account> =
    accounts.filter { it.writable && it.accountType in setOf("depository", "credit_card") }
        .sortedWith(compareBy<Account> { if (it.accountType == "depository") 0 else 1 }.thenBy { it.name.lowercase() })

/** A quick expense or income: the essentials up front, classification optional. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun TransactionCreator(state: TransactionCreateState, accounts: List<Account>, defaultAccountId: String?, vm: AppViewModel) {
    val choices = remember(accounts) { creatableAccounts(accounts) }
    val draft = state.draftId
    var income by rememberSaveable(draft) { mutableStateOf(false) }
    var amount by rememberSaveable(draft) { mutableStateOf("") }
    var name by rememberSaveable(draft) { mutableStateOf("") }
    var accountId by rememberSaveable(draft) {
        mutableStateOf(listOfNotNull(state.accountId, defaultAccountId).firstOrNull { id -> choices.any { it.id == id } } ?: choices.firstOrNull()?.id)
    }
    var date by rememberSaveable(draft) { mutableStateOf(LocalDate.now().toString()) }
    var categoryId by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var categoryLabel by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var categoryColor by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var categoryIconName by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var merchantId by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var merchantLabel by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var merchantLogo by rememberSaveable(draft) { mutableStateOf<String?>(null) }
    var tagIds by rememberSaveable(draft) { mutableStateOf(emptyList<String>()) }
    val knownTags = remember(draft) { mutableStateMapOf<String, TagRef>() }
    var notes by rememberSaveable(draft) { mutableStateOf("") }
    var shared by rememberSaveable(draft) { mutableStateOf(false) }
    var picker by rememberSaveable(draft) { mutableStateOf<Picker?>(null) }
    var pickingDate by rememberSaveable(draft) { mutableStateOf(false) }
    var pickingAccount by rememberSaveable(draft) { mutableStateOf(false) }

    val account = choices.find { it.id == accountId }
    val currency = account?.currency ?: "EUR"
    val parsed = parseAmount(amount)
    val validAmount = parsed != null && parsed.signum() > 0 && parsed.stripTrailingZeros().scale() <= currencyDigits(currency)
    val canSave = account != null && validAmount && name.isNotBlank()
    val busy = state.saving
    val saving by rememberUpdatedState(busy)
    val confirm = remember { { target: SheetValue -> target != SheetValue.Hidden || !saving } }
    val focus = remember { FocusRequester() }
    LaunchedEffect(draft) { runCatching { focus.requestFocus() } }

    ModalBottomSheet(
        onDismissRequest = vm::cancelCreate,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = confirm),
        containerColor = Relay.surface,
        contentColor = Relay.text,
    ) {
        Column(
            Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Nuevo movimiento", style = MaterialTheme.typography.titleLarge)
            if (choices.isEmpty()) {
                Text("No tienes cuentas corrientes ni tarjetas en las que puedas registrar movimientos.", color = Relay.muted,
                    style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = vm::cancelCreate, modifier = Modifier.align(Alignment.End)) { Text("Cerrar") }
                return@Column
            }
            NatureToggle(income, !busy) { income = it }
            OutlinedTextField(
                value = amount, onValueChange = { amount = it }, label = { Text("Importe · $currency") },
                singleLine = true, enabled = !busy, isError = amount.isNotBlank() && !validAmount,
                textStyle = MaterialTheme.typography.headlineSmall.merge(tabular).copy(fontWeight = FontWeight.SemiBold),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                supportingText = {
                    Text(when {
                        amount.isNotBlank() && !validAmount -> "Introduce un importe mayor que cero."
                        validAmount -> if (income) "Entrará ${formatMoney(parsed!!, currency)}" else "Saldrá ${formatMoney(parsed!!, currency)}"
                        else -> if (income) "Dinero que recibes" else "Dinero que pagas"
                    })
                },
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
            OutlinedTextField(
                value = name, onValueChange = { name = it }, label = { Text("Concepto") }, placeholder = { Text("Ej. Supermercado") },
                singleLine = true, enabled = !busy, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
            EditorChoice("Cuenta", account?.name ?: "Elige una cuenta", busy,
                leading = { account?.let { AccountBadge(it, 34.dp) } ?: IconBadge(Icons.Outlined.AccountBalanceWallet, Relay.muted, size = 34.dp) },
            ) { pickingAccount = true }
            EditorChoice("Fecha", numericDate(date), busy, dateChoice = true) { pickingDate = true }
            EditorChoice(
                "Categoría", categoryLabel ?: "Sin categoría", busy,
                leading = { IconBadge(categoryIcon(categoryIconName), if (categoryId == null) Relay.muted else categoryTone(categoryColor), size = 34.dp) },
            ) { picker = Picker.Category }
            EditorChoice(
                "Comercio", merchantLabel ?: "Sin comercio", busy,
                leading = {
                    val id = merchantId
                    val label = merchantLabel
                    if (id == null || label == null) IconBadge(Icons.Outlined.Storefront, Relay.muted, size = 34.dp)
                    else MerchantBadge(NamedRef(id, label, merchantLogo), 34.dp)
                },
            ) { picker = Picker.Merchant }
            TagsChoice(tagIds.mapNotNull(knownTags::get), busy) { picker = Picker.Tags }
            AnimatedVisibility(!income, enter = expandVertically(tween(Relay.BASE)) + fadeIn(), exit = shrinkVertically(tween(Relay.BASE)) + fadeOut()) {
                SharedExpenseCheck(shared, !busy) { shared = it }
            }
            NotesField(notes, !busy) { notes = it }
            state.error?.let { ErrorBanner(it) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = vm::cancelCreate, enabled = !busy) { Text("Cancelar") }
                GradientButton(
                    onClick = {
                        vm.createTransaction(buildJsonObject {
                            put("account_id", account!!.id)
                            put("name", name.trim())
                            put("amount", parsed!!.toPlainString())
                            put("nature", if (income) "income" else "expense")
                            put("date", date)
                            put("currency", currency)
                            categoryId?.let { put("category_id", it) }
                            merchantId?.let { put("merchant_id", it) }
                            if (tagIds.isNotEmpty()) put("tag_ids", JsonArray(tagIds.map { JsonPrimitive(it) }))
                            notes.trim().takeIf { it.isNotEmpty() }?.let { put("notes", it) }
                            if (!income && shared) put("shared_expense", true)
                        })
                    },
                    modifier = Modifier.weight(1f), enabled = canSave, busy = busy,
                ) { Text(if (income) "Guardar ingreso" else "Guardar gasto", color = Color.White) }
            }
        }
    }

    if (pickingAccount) AccountPicker(choices, accountId, onDismiss = { pickingAccount = false }) {
        accountId = it.id
        pickingAccount = false
    }
    if (pickingDate) EditDateDialog(date, onDismiss = { pickingDate = false }) { date = it }
    when (picker) {
        Picker.Category -> CategoryPicker(categoryId, vm, onDismiss = { picker = null }) { choice ->
            categoryId = choice?.id
            categoryLabel = choice?.let { option -> option.parent?.let { "${it.name} / ${option.name}" } ?: option.name }
            categoryColor = choice?.color
            categoryIconName = choice?.icon
            picker = null
        }
        Picker.Merchant -> MerchantPicker(merchantId, vm, onDismiss = { picker = null }) { choice ->
            merchantId = choice?.id
            merchantLabel = choice?.label
            merchantLogo = choice?.logoUrl
            picker = null
        }
        Picker.Tags -> TagPicker(tagIds, knownTags.values.toList(), vm, onDismiss = { picker = null }) { chosen ->
            chosen.forEach { knownTags[it.id] = it }
            tagIds = chosen.map { it.id }
            picker = null
        }
        null -> Unit
    }
}

/** Expense or income, as the web's transaction tabs. */
@Composable private fun NatureToggle(income: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Relay.surface2.copy(alpha = 0.7f)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        listOf(false to "Gasto", true to "Ingreso").forEach { (value, label) ->
            val active = value == income
            val tone = if (value) Relay.income else Relay.magenta
            val background by animateColorAsState(if (active) tone.copy(alpha = 0.2f) else tone.copy(alpha = 0f), tween(Relay.BASE), label = "nature")
            Box(
                Modifier.weight(1f).height(40.dp).clip(RoundedCornerShape(11.dp)).background(background)
                    .clickable(enabled = enabled && !active) { onChange(value) },
                contentAlignment = Alignment.Center,
            ) { Text(label, style = MaterialTheme.typography.labelLarge, color = if (active) tone else Relay.muted) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun AccountPicker(accounts: List<Account>, selectedId: String?, onDismiss: () -> Unit, onSelect: (Account) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Relay.surface, contentColor = Relay.text) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Cuenta", style = MaterialTheme.typography.titleLarge)
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 480.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(accounts, key = { it.id }) { account ->
                    val selected = account.id == selectedId
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                            .then(if (selected) Modifier.background(Relay.violet.copy(alpha = 0.14f)) else Modifier)
                            .clickable { onSelect(account) }.padding(horizontal = 10.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        AccountBadge(account, 40.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(account.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(formatMoney(account.balanceCents, account.currency), style = MaterialTheme.typography.labelMedium.merge(tabular),
                                color = Relay.muted)
                        }
                        if (selected) Icon(Icons.Outlined.Check, "Seleccionada", tint = Relay.violet)
                    }
                }
            }
        }
    }
}

/** Decimal input parsed the same way in the editor and the creator. */
internal fun parseAmount(text: String): BigDecimal? =
    text.trim().takeIf { it.matches(Regex("[0-9]+([,.][0-9]+)?")) }?.replace(',', '.')?.toBigDecimalOrNull()
