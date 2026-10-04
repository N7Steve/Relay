import Foundation
import Observation
import UserNotifications
import UIKit

@MainActor
@Observable
final class SureStore {
  var isConfigured = false
  var isLoading = false
  var errorMessage: String?
  var balanceSheet: BalanceSheet?
  var accounts: [SureAccount] = []
  var budgets: [SureBudget] = []
  var insights: [SureInsight] = []
  var selectedTab = SureTab.overview

  private(set) var baseURLString = "https://demo.sure.am"
  private var client = SureAPIClient(baseURL: URL(string: "https://demo.sure.am")!, apiKey: "")
  private var sessionGeneration = 0

  func restoreSession() async {
    let generation = sessionGeneration
    baseURLString = UserDefaults.standard.string(forKey: "sure.baseURL") ?? "https://demo.sure.am"
    guard let key = KeychainStore.readAPIKey(), !key.isEmpty,
          let url = normalizedURL(baseURLString) else { return }
    await client.update(baseURL: url, apiKey: key)
    guard sessionGeneration == generation else { return }
    do {
      let balance: BalanceSheet = try await client.get("api/v1/balance_sheet")
      guard sessionGeneration == generation else { return }
      balanceSheet = balance
      isConfigured = true
      await refreshAll()
    } catch {
      guard sessionGeneration == generation else { return }
      errorMessage = "Your saved connection needs attention. \(error.localizedDescription)"
    }
  }

  func connect(baseURL: String, apiKey: String) async -> Bool {
    guard let url = normalizedURL(baseURL) else {
      errorMessage = "Enter a valid HTTPS server address."
      return false
    }
    sessionGeneration &+= 1
    let generation = sessionGeneration
    isLoading = true
    errorMessage = nil
    await client.update(baseURL: url, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
    guard sessionGeneration == generation else { return false }
    do {
      let balance: BalanceSheet = try await client.get("api/v1/balance_sheet")
      guard sessionGeneration == generation else { return false }
      balanceSheet = balance
      try KeychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
      baseURLString = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      UserDefaults.standard.set(baseURLString, forKey: "sure.baseURL")
      isConfigured = true
      isLoading = false
      await refreshAll()
      return sessionGeneration == generation
    } catch {
      guard sessionGeneration == generation else { return false }
      errorMessage = error.localizedDescription
      isLoading = false
      return false
    }
  }

  func disconnect() async {
    sessionGeneration &+= 1
    await unregisterPushToken()
    KeychainStore.deleteAPIKey()
    UserDefaults.standard.removeObject(forKey: "sure.pushSubscriptionID")
    UserDefaults.standard.set(false, forKey: "sure.insightNotifications")
    isConfigured = false
    isLoading = false
    errorMessage = nil
    balanceSheet = nil
    accounts = []
    budgets = []
    insights = []
  }

  func refreshAll() async {
    let generation = sessionGeneration
    isLoading = true
    errorMessage = nil
    async let balanceRequest: BalanceSheet = client.get("api/v1/balance_sheet")
    async let accountsRequest = loadAllPages(
      path: "api/v1/accounts",
      collection: AccountCollection.self,
      items: \.accounts
    )
    async let budgetsRequest = loadAllPages(
      path: "api/v1/budgets",
      collection: BudgetCollection.self,
      items: \.budgets
    )
    do {
      let (balance, loadedAccounts, loadedBudgets) = try await (
        balanceRequest,
        accountsRequest,
        budgetsRequest
      )
      guard sessionGeneration == generation else { return }
      balanceSheet = balance
      accounts = loadedAccounts
      budgets = loadedBudgets
    } catch {
      guard sessionGeneration == generation else { return }
      errorMessage = error.localizedDescription
      isLoading = false
      return
    }

    await loadInsights()
    guard sessionGeneration == generation else { return }
    if UserDefaults.standard.bool(forKey: "sure.insightNotifications") {
      if let token = UserDefaults.standard.string(forKey: "sure.apnsDeviceToken") {
        await registerPushToken(token)
      }
    } else {
      await unregisterPushToken()
    }
    guard sessionGeneration == generation else { return }
    isLoading = false
  }

  func loadInsights() async {
    let generation = sessionGeneration
    do {
      let collection: InsightCollection = try await client.get("api/v1/insights")
      guard sessionGeneration == generation else { return }
      insights = collection.insights
    } catch let error as SureAPIError {
      guard sessionGeneration == generation else { return }
      if case .server(status: 404, message: _) = error {
        insights = makeLocalInsights()
      } else if case .server(status: 403, message: _) = error {
        insights = []
      } else {
        errorMessage = error.localizedDescription
      }
    } catch {
      guard sessionGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }

  func registerPushToken(_ token: String) async {
    guard isConfigured, UserDefaults.standard.bool(forKey: "sure.insightNotifications") else { return }
    let generation = sessionGeneration
    let environment = APNsEnvironment.current
    let request = PushSubscriptionRequest(
      token: token,
      environment: environment.rawValue,
      platform: "ios"
    )
    do {
      let receipt: PushSubscriptionReceipt = try await client.post(
        "api/v1/push_subscriptions",
        body: request
      )
      guard sessionGeneration == generation else {
        try? await client.delete("api/v1/push_subscriptions/\(receipt.id)")
        return
      }
      UserDefaults.standard.set(receipt.id, forKey: "sure.pushSubscriptionID")
    } catch let error as SureAPIError {
      guard sessionGeneration == generation else { return }
      if case .server(status: 404, message: _) = error { return }
      errorMessage = error.localizedDescription
    } catch {
      guard sessionGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }

  func unregisterPushToken() async {
    guard isConfigured,
          let id = UserDefaults.standard.string(forKey: "sure.pushSubscriptionID") else { return }
    let generation = sessionGeneration
    do {
      try await client.delete("api/v1/push_subscriptions/\(id)")
      guard sessionGeneration == generation else { return }
      UserDefaults.standard.removeObject(forKey: "sure.pushSubscriptionID")
    } catch let error as SureAPIError {
      guard sessionGeneration == generation else { return }
      if case .server(status: 404, message: _) = error {
        UserDefaults.standard.removeObject(forKey: "sure.pushSubscriptionID")
        return
      }
      errorMessage = error.localizedDescription
    } catch {
      guard sessionGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
  }

  private func loadAllPages<Collection: Decodable & Sendable, Item: Sendable>(
    path: String,
    collection: Collection.Type,
    items: KeyPath<Collection, [Item]>
  ) async throws -> [Item] where Collection: PaginatedCollection {
    let firstPage = try await client.get("\(path)?page=1&per_page=100", as: collection)
    var allItems = firstPage[keyPath: items]
    let totalPages = firstPage.pagination?.totalPages ?? 1
    guard totalPages > 1 else { return allItems }

    for page in 2...totalPages {
      let nextPage = try await client.get("\(path)?page=\(page)&per_page=100", as: collection)
      allItems.append(contentsOf: nextPage[keyPath: items])
    }
    return allItems
  }

  private func makeLocalInsights() -> [SureInsight] {
    var generated: [SureInsight] = []
    if let balanceSheet {
      let liabilities = balanceSheet.liabilities.decimalAmount.magnitude
      let assets = balanceSheet.assets.decimalAmount.magnitude
      if liabilities > 0, assets > 0 {
        let ratio = NSDecimalNumber(decimal: liabilities / assets).doubleValue
        generated.append(SureInsight(
          id: "live-debt-ratio",
          type: ratio > 0.5 ? "cash_flow_warning" : "budget_on_track",
          title: ratio > 0.5 ? "Liabilities need attention" : "Your balance sheet looks resilient",
          body: "Liabilities are \((ratio * 100).formatted(.number.precision(.fractionLength(0))))% of assets, based on your live Relay balances.",
          priority: ratio > 0.5 ? "high" : "low",
          status: "active"
        ))
      }
    }
    if let largest = accounts.filter(\.isAsset).max(by: { abs($0.balanceCents) < abs($1.balanceCents) }) {
      generated.append(SureInsight(
        id: "live-largest-account",
        type: "idle_cash",
        title: "Review your largest account",
        body: "\(largest.name) holds \(largest.balance). Review whether that concentration fits your goals.",
        priority: "medium",
        status: "active"
      ))
    }
    if let currentBudget = budgets.first(where: \.current) {
      generated.append(SureInsight(
        id: "live-current-budget",
        type: "budget_on_track",
        title: "Your current plan is ready to review",
        body: "\(currentBudget.name) has \(currentBudget.allocatedSpending) allocated. Check it before the period ends.",
        priority: "low",
        status: "active"
      ))
    }
    return Array(generated.prefix(3))
  }

  private func normalizedURL(_ input: String) -> URL? {
    guard var components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
          components.scheme == "https", components.host != nil else { return nil }
    components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
    return components.url
  }
}

enum SureTab: Hashable {
  case overview
  case accounts
  case budgets
}

protocol PaginatedCollection {
  var pagination: SurePagination? { get }
}

extension AccountCollection: PaginatedCollection {}
extension BudgetCollection: PaginatedCollection {}

struct PushSubscriptionRequest: Codable, Sendable {
  var token: String
  var environment: String
  var platform: String
}

struct PushSubscriptionReceipt: Codable, Sendable {
  var id: String
}

enum APNsEnvironment: String {
  case sandbox
  case production

  static var current: APNsEnvironment {
    #if targetEnvironment(simulator)
    return .sandbox
    #else
    guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let profileData = try? Data(contentsOf: profileURL),
          let profileText = String(data: profileData, encoding: .isoLatin1) else {
      return .production
    }
    return profileText.contains("<string>development</string>") ? .sandbox : .production
    #endif
  }
}
