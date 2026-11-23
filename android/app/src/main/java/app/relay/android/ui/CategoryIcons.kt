package app.relay.android.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/** Relay stores Lucide icon names on categories; these are their closest Material equivalents. */
private val lucide: Map<String, ImageVector> by lazy {
    with(Icons.Outlined) {
        mapOf(
            "activity" to MonitorHeart, "alarm-clock" to Alarm, "ambulance" to LocalHospital, "anchor" to Anchor,
            "archive" to Archive, "award" to EmojiEvents, "baby" to ChildCare, "backpack" to Backpack,
            "badge-dollar-sign" to Paid, "banknote" to Payments, "barcode" to QrCode, "bar-chart-3" to BarChart,
            "bath" to Bathtub, "battery" to BatteryFull, "bed-double" to Bed, "bed-single" to Bed, "beer" to SportsBar,
            "bell" to Notifications, "bike" to DirectionsBike, "bitcoin" to CurrencyBitcoin, "bluetooth" to Bluetooth,
            "bone" to Pets, "book" to MenuBook, "book-open" to AutoStories, "box" to Inventory2, "briefcase" to Work,
            "brush" to Brush, "building" to Business, "bus" to DirectionsBus, "cake" to Cake, "calculator" to Calculate,
            "calendar-heart" to Event, "calendar-range" to DateRange, "camera" to PhotoCamera, "candy" to Icecream,
            "car" to DirectionsCar, "cat" to Pets, "chart-line" to ShowChart, "church" to Church,
            "cigarette" to SmokingRooms, "circle-dollar-sign" to MonetizationOn, "circle-parking" to LocalParking,
            "clipboard" to Assignment, "clock" to Schedule, "cloud" to Cloud, "coffee" to LocalCafe, "coins" to Toll,
            "compass" to Explore, "construction" to Construction, "cookie" to Cookie, "cooking-pot" to SoupKitchen,
            "credit-card" to CreditCard, "crown" to WorkspacePremium, "cup-soda" to LocalDrink, "dices" to Casino,
            "dog" to Pets, "door-closed" to DoorFront, "door-open" to MeetingRoom, "drama" to TheaterComedy,
            "drill" to Handyman, "droplet" to WaterDrop, "drum" to MusicNote, "dumbbell" to FitnessCenter,
            "ear" to Hearing, "egg" to Egg, "eye" to Visibility, "factory" to Factory, "fan" to Air, "fence" to Fence,
            "ferris-wheel" to Attractions, "film" to Movie, "fingerprint" to Fingerprint, "fish" to SetMeal,
            "flag" to Flag, "flame" to LocalFireDepartment, "flashlight" to FlashlightOn, "flower" to LocalFlorist,
            "flower-2" to LocalFlorist, "fuel" to LocalGasStation, "gamepad-2" to SportsEsports, "gem" to Diamond,
            "gift" to CardGiftcard, "globe" to Public, "graduation-cap" to School, "guitar" to MusicNote,
            "hammer" to Hardware, "hand-coins" to Payments, "hand-heart" to VolunteerActivism,
            "hand-helping" to VolunteerActivism, "handshake" to Handshake, "headphones" to Headphones,
            "heart" to FavoriteBorder, "heart-handshake" to VolunteerActivism, "heart-pulse" to MonitorHeart,
            "home" to Home, "house" to Home, "hotel" to Hotel, "ice-cream-cone" to Icecream, "key" to Key,
            "lamp" to Lightbulb, "landmark" to AccountBalance, "laptop" to Laptop, "laugh" to SentimentVerySatisfied,
            "leaf" to Eco, "library" to LocalLibrary, "lightbulb" to Lightbulb, "lock" to Lock, "luggage" to Luggage,
            "mail" to Mail, "map" to Icons.Outlined.Map, "map-pin" to Place, "martini" to LocalBar, "megaphone" to Campaign,
            "mic" to Mic, "microscope" to Biotech, "milk" to LocalDrink, "monitor" to Monitor, "moon" to DarkMode,
            "mountain" to Terrain, "mountain-snow" to Terrain, "music" to MusicNote, "newspaper" to Newspaper,
            "package" to Inventory2, "paintbrush" to Brush, "palette" to Palette, "party-popper" to Celebration,
            "paw-print" to Pets, "pen" to Edit, "pencil" to Edit, "percent" to Percent, "phone" to Phone,
            "pickaxe" to Hardware, "pie-chart" to PieChart, "piggy-bank" to Savings, "pill" to Medication,
            "pizza" to LocalPizza, "plane" to Flight, "plug" to Power, "podcast" to Podcasts,
            "popcorn" to Theaters, "power" to PowerSettingsNew, "printer" to Print, "puzzle" to Extension,
            "rabbit" to Pets, "radio" to Radio, "receipt" to Receipt, "receipt-text" to ReceiptLong,
            "refrigerator" to Kitchen, "rocket" to RocketLaunch, "ruler" to Straighten, "sailboat" to Sailing,
            "sandwich" to LunchDining, "scale" to Balance, "school" to School, "scissors" to ContentCut,
            "settings" to Settings, "shapes" to Category, "shield" to Shield, "shield-plus" to HealthAndSafety,
            "ship" to DirectionsBoat, "shirt" to Checkroom, "shopping-bag" to ShoppingBag,
            "shopping-basket" to ShoppingBasket, "shopping-cart" to ShoppingCart, "shovel" to Agriculture,
            "smartphone" to Smartphone, "snowflake" to AcUnit, "sofa" to Weekend, "soup" to RamenDining,
            "sparkles" to AutoAwesome, "sprout" to Spa, "star" to StarBorder, "stethoscope" to MedicalServices,
            "store" to Store, "sun" to WbSunny, "syringe" to Vaccines, "tablet-smartphone" to Devices,
            "tag" to LocalOffer, "target" to Adjust, "tent" to Cabin, "thermometer" to Thermostat,
            "ticket" to ConfirmationNumber, "timer" to Timer, "tractor" to Agriculture, "train" to Train,
            "trees" to Park, "tree-palm" to BeachAccess, "trending-down" to TrendingDown, "trending-up" to TrendingUp,
            "trophy" to EmojiEvents, "truck" to LocalShipping, "tv" to Tv, "umbrella" to Umbrella, "undo-2" to Undo,
            "unplug" to PowerOff, "users" to Group, "utensils" to Restaurant, "video" to Videocam,
            "wallet" to AccountBalanceWallet, "wallet-cards" to AccountBalanceWallet,
            "washing-machine" to LocalLaundryService, "waves" to Waves, "wheat" to Grass, "wifi" to Wifi,
            "wine" to WineBar, "wrench" to Build, "zap" to Bolt, "circle-dashed" to RadioButtonUnchecked,
            "arrow-right-left" to SwapHoriz,
        )
    }
}

/** Relay's mark for movements without a category. */
const val UNCATEGORIZED_ICON = "circle-dashed"

fun categoryIcon(name: String?): ImageVector = name?.let(lucide::get) ?: Icons.Outlined.Category

/** Relay's own colours (#rrggbb), or a neutral tone. */
fun categoryTone(color: String?): Color = color?.let(::parseHex) ?: Relay.secondary

/** Distinct hues for chart rows whose category has no colour of its own. */
val chartPalette = listOf(Relay.cyan, Relay.violet, Relay.magenta, Relay.blue, Relay.warning, Relay.income,
    Color(0xFFFB923C), Color(0xFF2DD4BF), Color(0xFFF472B6), Color(0xFFA3E635))
