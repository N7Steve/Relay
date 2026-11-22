package app.relay.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.relay.android.data.NamedRef
import app.relay.android.data.Transaction
import app.relay.android.data.currencyDigits
import app.relay.android.data.minorToDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private enum class Picker(val title: String, val emptyLabel: String) {
    Category("Categoría", "Sin categoría"),
    Merchant("Comercio", "Sin comercio"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun TransactionEditor(transaction: Transaction, state: TransactionEditState, vm: AppViewModel) {
    val fields = transaction.editableFields
    val originalAmount = minorToDecimal(transaction.amountCents, transaction.currency)
    var name by rememberSaveable(transaction.id) { mutableStateOf(transaction.name) }
    var amount by rememberSaveable(transaction.id) { mutableStateOf(originalAmount.toPlainString().replace('.', ',')) }
    var date by rememberSaveable(transaction.id) { mutableStateOf(transaction.date) }
    var categoryId by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.id) }
    var categoryLabel by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.name) }
    var merchantId by rememberSaveable(transaction.id) { mutableStateOf(transaction.merchant?.id) }
    var merchantLabel by rememberSaveable(transaction.id) { mutableStateOf(transaction.merchant?.name) }
    var picker by rememberSaveable(transaction.id) { mutableStateOf<Picker?>(null) }
    var pickingDate by rememberSaveable(transaction.id) { mutableStateOf(false) }

    val parsed = amount.trim().takeIf { it.matches(Regex("[0-9]+([,.][0-9]+)?")) }
        ?.replace(',', '.')?.toBigDecimalOrNull()
    val validAmount = parsed != null && parsed.stripTrailingZeros().scale() <= currencyDigits(transaction.currency) &&
        runCatching { parsed.movePointRight(currencyDigits(transaction.currency)).longValueExact() }.isSuccess
    val nameChanged = name != transaction.name
    val changes = buildJsonObject {
        if ("name" in fields && nameChanged) put("name", name.trim())
        if ("date" in fields && date != transaction.date) put("date", date)
        if ("amount" in fields && parsed != null && parsed.compareTo(originalAmount) != 0) {
            put("amount", if (transaction.isIncome) parsed.negate().toPlainString() else parsed.toPlainString())
        }
        if ("category_id" in fields && categoryId != transaction.category?.id) {
            categoryId?.let { put("category_id", it) } ?: put("category_id", JsonNull)
        }
        if ("merchant_id" in fields && merchantId != transaction.merchant?.id) {
            merchantId?.let { put("merchant_id", it) } ?: put("merchant_id", JsonNull)
        }
    }
    val canSave = changes.isNotEmpty() && !(nameChanged && name.isBlank()) && ("amount" !in fields || validAmount)
    val saving by rememberUpdatedState(state.saving)
    val confirmSheetState = remember { { target: SheetValue -> target != SheetValue.Hidden || !saving } }

    ModalBottomSheet(
        onDismissRequest = vm::cancelEdit,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = confirmSheetState),
        containerColor = Relay.surface,
        contentColor = Relay.text,
    ) {
        Column(
            Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Editar movimiento", style = MaterialTheme.typography.titleLarge)
            if ("name" in fields) OutlinedTextField(
                value = name, onValueChange = { name = it }, label = { Text("Nombre") },
                singleLine = true, enabled = !state.saving, isError = nameChanged && name.isBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) else Text(transaction.name, color = Relay.muted)
            if ("amount" in fields) OutlinedTextField(
                value = amount, onValueChange = { amount = it }, label = { Text("Importe · ${transaction.currency}") },
                singleLine = true, enabled = !state.saving, isError = !validAmount,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                supportingText = {
                    Text(if (!validAmount) "Introduce un importe válido." else if (transaction.isIncome) "Ingreso" else "Gasto")
                },
                modifier = Modifier.fillMaxWidth(),
            )
            if ("date" in fields) EditorChoice("Fecha", dayLabel(date), state.saving, dateChoice = true) { pickingDate = true }
            if ("category_id" in fields) EditorChoice("Categoría", categoryLabel ?: "Sin categoría", state.saving) { picker = Picker.Category }
            if ("merchant_id" in fields) EditorChoice("Comercio", merchantLabel ?: "Sin comercio", state.saving) { picker = Picker.Merchant }
            state.error?.let { ErrorBanner(it) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = vm::cancelEdit, enabled = !state.saving) { Text("Cancelar") }
                GradientButton(onClick = { vm.saveTransaction(changes) }, modifier = Modifier.weight(1f), enabled = canSave, busy = state.saving) {
                    Text("Guardar cambios", color = Color.White)
                }
            }
        }
    }

    if (pickingDate) EditDateDialog(date, onDismiss = { pickingDate = false }) { date = it }
    picker?.let { selection ->
        ReferenceDialog(
            selection, if (selection == Picker.Category) categoryId else merchantId, vm,
            onDismiss = { picker = null },
            onSelect = { choice ->
                when (selection) {
                    Picker.Category -> { categoryId = choice?.id; categoryLabel = choice?.label }
                    Picker.Merchant -> { merchantId = choice?.id; merchantLabel = choice?.label }
                }
                picker = null
            },
        )
    }
}

@Composable private fun EditorChoice(label: String, value: String, busy: Boolean, dateChoice: Boolean = false, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
        Column(Modifier.weight(1f).padding(vertical = 3.dp)) {
            Text(label, color = Relay.muted, style = MaterialTheme.typography.labelMedium)
            Text(value, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
        }
        Icon(if (dateChoice) Icons.Outlined.CalendarToday else Icons.Outlined.ExpandMore, null, tint = Relay.secondary)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun EditDateDialog(date: String, onDismiss: () -> Unit, onSelect: (String) -> Unit) {
    val selected = rememberDatePickerState(initialSelectedDateMillis = LocalDate.parse(date).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                enabled = selected.selectedDateMillis != null,
                onClick = {
                    selected.selectedDateMillis?.let { onSelect(Instant.ofEpochMilli(it).atOffset(ZoneOffset.UTC).toLocalDate().toString()) }
                    onDismiss()
                },
            ) { Text("Aceptar") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancelar") } },
    ) { DatePicker(selected) }
}

@Composable private fun ReferenceDialog(picker: Picker, selectedId: String?, vm: AppViewModel, onDismiss: () -> Unit, onSelect: (NamedRef?) -> Unit) {
    var query by rememberSaveable(picker) { mutableStateOf("") }
    var attempt by rememberSaveable(picker) { mutableStateOf(0) }
    val result by produceState<Result<List<NamedRef>>?>(null, picker, attempt) {
        value = null
        value = try {
            Result.success(when (picker) { Picker.Category -> vm.categories(); Picker.Merchant -> vm.merchants() })
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Result.failure(error)
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Relay.surface2,
        title = { Text(picker.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, label = { Text("Buscar") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                )
                val filtered = result?.getOrNull().orEmpty().filter { it.label.contains(query.trim(), ignoreCase = true) }
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 300.dp)) {
                    item { ReferenceOption(picker.emptyLabel, selectedId == null) { onSelect(null) } }
                    items(filtered, key = { it.id }) { option ->
                        ReferenceOption(option.label, option.id == selectedId) { onSelect(option) }
                    }
                    if (result?.isSuccess == true && query.isNotBlank() && filtered.isEmpty()) {
                        item { Text("Sin coincidencias", color = Relay.muted, modifier = Modifier.padding(12.dp)) }
                    }
                }
                if (result == null) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
                result?.exceptionOrNull()?.let { ErrorBanner(vm.describe(it), onRetry = { attempt++ }) }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Cerrar") } },
    )
}

@Composable private fun ReferenceOption(label: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        trailingIcon = if (selected) ({ Icon(Icons.Outlined.Check, "Seleccionado") }) else null,
        onClick = onClick,
    )
}
