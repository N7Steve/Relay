package app.relay.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Search
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
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.relay.android.data.CategoryOption
import app.relay.android.data.NamedRef
import app.relay.android.data.TagRef
import app.relay.android.data.Transaction
import app.relay.android.data.currencyDigits
import app.relay.android.data.minorToDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

private enum class Picker { Category, Merchant, Tags }

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun TransactionEditor(transaction: Transaction, state: TransactionEditState, vm: AppViewModel) {
    val fields = transaction.editableFields
    val originalAmount = minorToDecimal(transaction.amountCents, transaction.currency)
    var name by rememberSaveable(transaction.id) { mutableStateOf(transaction.name) }
    var amount by rememberSaveable(transaction.id) { mutableStateOf(originalAmount.toPlainString().replace('.', ',')) }
    var date by rememberSaveable(transaction.id) { mutableStateOf(transaction.date) }
    var categoryId by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.id) }
    var categoryLabel by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.name) }
    var categoryColor by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.color) }
    var categoryIconName by rememberSaveable(transaction.id) { mutableStateOf(transaction.category?.icon) }
    var merchantId by rememberSaveable(transaction.id) { mutableStateOf(transaction.merchant?.id) }
    var merchantLabel by rememberSaveable(transaction.id) { mutableStateOf(transaction.merchant?.name) }
    var tagIds by rememberSaveable(transaction.id) { mutableStateOf(transaction.tags.map { it.id }) }
    // Names and colours for the chips; ids alone survive configuration changes.
    val knownTags = remember(transaction.id) { mutableStateMapOf<String, TagRef>().apply { transaction.tags.forEach { put(it.id, it) } } }
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
        if ("tag_ids" in fields && tagIds.toSet() != transaction.tags.map { it.id }.toSet()) {
            put("tag_ids", JsonArray(tagIds.map { JsonPrimitive(it) }))
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
            if ("date" in fields) EditorChoice("Fecha", numericDate(date), state.saving, dateChoice = true) { pickingDate = true }
            if ("category_id" in fields) EditorChoice(
                "Categoría", categoryLabel ?: "Sin categoría", state.saving,
                leading = { IconBadge(categoryIcon(categoryIconName), if (categoryId == null) Relay.muted else categoryTone(categoryColor), size = 34.dp) },
            ) { picker = Picker.Category }
            if ("merchant_id" in fields) EditorChoice("Comercio", merchantLabel ?: "Sin comercio", state.saving) { picker = Picker.Merchant }
            if ("tag_ids" in fields) TagsChoice(tagIds.mapNotNull(knownTags::get), state.saving) { picker = Picker.Tags }
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
    when (picker) {
        Picker.Category -> CategoryPicker(categoryId, vm, onDismiss = { picker = null }) { choice ->
            categoryId = choice?.id
            categoryLabel = choice?.let { option -> option.parent?.let { "${it.name} / ${option.name}" } ?: option.name }
            categoryColor = choice?.color
            categoryIconName = choice?.icon
            picker = null
        }
        Picker.Merchant -> MerchantDialog(merchantId, vm, onDismiss = { picker = null }) { choice ->
            merchantId = choice?.id
            merchantLabel = choice?.label
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

@Composable private fun EditorChoice(
    label: String,
    value: String,
    busy: Boolean,
    dateChoice: Boolean = false,
    leading: (@Composable () -> Unit)? = null,
    onClick: () -> Unit,
) {
    OutlinedButton(onClick = onClick, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
        leading?.let {
            it()
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f).padding(vertical = 3.dp)) {
            Text(label, color = Relay.muted, style = MaterialTheme.typography.labelMedium)
            Text(value, color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
        }
        Icon(if (dateChoice) Icons.Outlined.CalendarToday else Icons.Outlined.ExpandMore, null, tint = Relay.secondary)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable private fun TagsChoice(tags: List<TagRef>, busy: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = !busy, modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium) {
        Column(Modifier.weight(1f).padding(vertical = 3.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Etiquetas", color = Relay.muted, style = MaterialTheme.typography.labelMedium)
            if (tags.isEmpty()) {
                Text("Sin etiquetas", color = Relay.text, style = MaterialTheme.typography.bodyLarge)
            } else {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    tags.forEach { TagChip(it) }
                }
            }
        }
        Icon(Icons.Outlined.ExpandMore, null, tint = Relay.secondary)
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

/** Loads picker options once per attempt; failures stay retryable. */
@Composable private fun <T> rememberOptions(attempt: Int, load: suspend () -> List<T>): Result<List<T>>? {
    val result by produceState<Result<List<T>>?>(null, attempt) {
        value = null
        value = try {
            Result.success(load())
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            Result.failure(error)
        }
    }
    return result
}

@Composable private fun PickerSearch(query: String, onChange: (String) -> Unit, placeholder: String) {
    OutlinedTextField(
        value = query, onValueChange = onChange, singleLine = true, modifier = Modifier.fillMaxWidth(),
        placeholder = { Text(placeholder, color = Relay.subtle) },
        leadingIcon = { Icon(Icons.Outlined.Search, null, tint = Relay.muted) },
        shape = MaterialTheme.shapes.medium,
    )
}

@Composable private fun PickerStatus(result: Result<*>?, vm: AppViewModel, empty: Boolean, onRetry: () -> Unit) {
    when {
        result == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.size(26.dp), color = Relay.violet, strokeWidth = 2.5.dp)
        }
        result.isFailure -> ErrorBanner(vm.describe(result.exceptionOrNull()!!), Modifier.padding(vertical = 8.dp), onRetry)
        empty -> Text("Sin coincidencias", color = Relay.muted, modifier = Modifier.padding(12.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun CategoryPicker(selectedId: String?, vm: AppViewModel, onDismiss: () -> Unit, onSelect: (CategoryOption?) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var attempt by rememberSaveable { mutableStateOf(0) }
    val result = rememberOptions(attempt) { vm.categories() }
    val all = result?.getOrNull().orEmpty()
    val search = query.trim()
    // Parents alphabetically, each followed by its subcategories; a flat match list while searching.
    val rows = remember(all, search) {
        if (search.isNotEmpty()) {
            all.filter { it.name.contains(search, true) || it.parent?.name?.contains(search, true) == true }.map { it to (it.parent != null) }
        } else {
            val ids = all.map { it.id }.toSet()
            val children = all.filter { it.parent != null }.groupBy { it.parent!!.id }
            all.filter { it.parent == null }.flatMap { parent -> listOf(parent to false) + children[parent.id].orEmpty().map { it to true } } +
                all.filter { it.parent != null && it.parent.id !in ids }.map { it to false }
        }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Relay.surface, contentColor = Relay.text) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Categoría", style = MaterialTheme.typography.titleLarge)
            PickerSearch(query, { query = it }, "Buscar categoría")
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (search.isEmpty()) item(key = "none") {
                    CategoryRow("Sin categoría", null, Relay.muted, categoryIcon("circle-dashed"), child = false, selected = selectedId == null) { onSelect(null) }
                }
                items(rows, key = { it.first.id }) { (option, child) ->
                    CategoryRow(option.name, option.parent?.name?.takeIf { search.isNotEmpty() }, categoryTone(option.color), categoryIcon(option.icon),
                        child = child && search.isEmpty(), selected = option.id == selectedId) { onSelect(option) }
                }
                item(key = "status") { PickerStatus(result, vm, empty = result?.isSuccess == true && rows.isEmpty()) { attempt++ } }
            }
        }
    }
}

@Composable private fun CategoryRow(
    name: String,
    parent: String?,
    tone: Color,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    child: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(start = if (child) 24.dp else 0.dp).clip(RoundedCornerShape(14.dp))
            .then(if (selected) Modifier.background(tone.copy(alpha = 0.14f)) else Modifier)
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconBadge(icon, tone, size = if (child) 32.dp else 40.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            parent?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = Relay.muted, maxLines = 1) }
            Text(name, style = if (child) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.bodyLarge,
                color = Relay.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (selected) Icon(Icons.Outlined.Check, "Seleccionada", tint = tone)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun TagPicker(
    selectedIds: List<String>,
    known: List<TagRef>,
    vm: AppViewModel,
    onDismiss: () -> Unit,
    onApply: (List<TagRef>) -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var attempt by rememberSaveable { mutableStateOf(0) }
    val chosen = remember { mutableStateListOf<String>().apply { addAll(selectedIds) } }
    val result = rememberOptions(attempt) { vm.tags() }
    // Tags already on the movement stay visible even when they belong to someone else.
    val all = remember(result, known) { (result?.getOrNull().orEmpty() + known).distinctBy { it.id }.sortedBy { it.name.lowercase() } }
    val search = query.trim()
    val rows = all.filter { search.isEmpty() || it.name.contains(search, true) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Relay.surface, contentColor = Relay.text) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(horizontal = 20.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Etiquetas", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                if (chosen.isNotEmpty()) TextButton(onClick = { chosen.clear() }) { Text("Quitar todas", color = Relay.muted) }
            }
            PickerSearch(query, { query = it }, "Buscar etiqueta")
            LazyColumn(Modifier.fillMaxWidth().heightIn(max = 440.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(rows, key = { it.id }) { tag ->
                    val selected = tag.id in chosen
                    val tone = categoryTone(tag.color)
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                            .then(if (selected) Modifier.background(tone.copy(alpha = 0.12f)) else Modifier)
                            .clickable { if (selected) chosen.remove(tag.id) else chosen.add(tag.id) }
                            .padding(horizontal = 10.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(32.dp).clip(CircleShape).background(tone.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                            Box(Modifier.size(12.dp).clip(CircleShape).background(tone))
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(tag.name, style = MaterialTheme.typography.bodyLarge, color = Relay.text, modifier = Modifier.weight(1f),
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Icon(if (selected) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                            if (selected) "Seleccionada" else null, tint = if (selected) tone else Relay.muted)
                    }
                }
                item(key = "status") { PickerStatus(result, vm, empty = result?.isSuccess == true && rows.isEmpty()) { attempt++ } }
            }
            GradientButton(onClick = { onApply(chosen.mapNotNull { id -> all.find { it.id == id } }) }, modifier = Modifier.fillMaxWidth(),
                enabled = result?.isSuccess == true) {
                Text(if (chosen.isEmpty()) "Sin etiquetas" else "Aplicar ${chosen.size} etiqueta${if (chosen.size == 1) "" else "s"}", color = Color.White)
            }
        }
    }
}

@Composable private fun MerchantDialog(selectedId: String?, vm: AppViewModel, onDismiss: () -> Unit, onSelect: (NamedRef?) -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var attempt by rememberSaveable { mutableStateOf(0) }
    val result = rememberOptions(attempt) { vm.merchants() }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Relay.surface2,
        title = { Text("Comercio") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, label = { Text("Buscar") },
                    modifier = Modifier.fillMaxWidth(), singleLine = true,
                )
                val filtered = result?.getOrNull().orEmpty().filter { it.label.contains(query.trim(), ignoreCase = true) }
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 300.dp)) {
                    item { ReferenceOption("Sin comercio", selectedId == null) { onSelect(null) } }
                    items(filtered, key = { it.id }) { option ->
                        ReferenceOption(option.label, option.id == selectedId) { onSelect(option) }
                    }
                    item { PickerStatus(result, vm, empty = result?.isSuccess == true && query.isNotBlank() && filtered.isEmpty()) { attempt++ } }
                }
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
