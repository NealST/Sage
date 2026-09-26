//
//  search.swift
//  CodexAPI
//
//  Port of codex-rs/codex-api/src/search.rs (Apache-2.0).
//  Upstream revision: 0a2eb4696c26ac33204bcd255721ab30220a4774
//  Port status: faithful
//
//  Standalone web-search request/response DTOs. `schemars` is omitted.
//

import CodexProtocol
import Foundation

public struct SearchRequest: Equatable, Sendable {
    public var id: String
    public var model: String
    public var reasoning: Reasoning?
    public var input: SearchInput?
    public var commands: SearchCommands?
    public var settings: SearchSettings?
    public var maxOutputTokens: UInt64?

    public init(
        id: String,
        model: String,
        reasoning: Reasoning? = nil,
        input: SearchInput? = nil,
        commands: SearchCommands? = nil,
        settings: SearchSettings? = nil,
        maxOutputTokens: UInt64? = nil
    ) {
        self.id = id
        self.model = model
        self.reasoning = reasoning
        self.input = input
        self.commands = commands
        self.settings = settings
        self.maxOutputTokens = maxOutputTokens
    }
}

extension SearchRequest: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id, model, reasoning, input, commands, settings
        case maxOutputTokens = "max_output_tokens"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(input, forKey: .input)
        try container.encodeIfPresent(commands, forKey: .commands)
        try container.encodeIfPresent(settings, forKey: .settings)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
    }
}

public enum SearchInput: Equatable, Sendable {
    case text(String)
    case items([ResponseItem])
}

extension SearchInput: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .items(let items):
            try container.encode(items)
        }
    }
}

public struct SearchCommands: Equatable, Sendable {
    public var searchQuery: [SearchQuery]?
    public var imageQuery: [SearchQuery]?
    public var open: [OpenOperation]?
    public var click: [ClickOperation]?
    public var find: [FindOperation]?
    public var screenshot: [ScreenshotOperation]?
    public var finance: [FinanceOperation]?
    public var weather: [WeatherOperation]?
    public var sports: [SportsOperation]?
    public var time: [TimeOperation]?
    public var responseLength: SearchResponseLength?

    public init(
        searchQuery: [SearchQuery]? = nil,
        imageQuery: [SearchQuery]? = nil,
        open: [OpenOperation]? = nil,
        click: [ClickOperation]? = nil,
        find: [FindOperation]? = nil,
        screenshot: [ScreenshotOperation]? = nil,
        finance: [FinanceOperation]? = nil,
        weather: [WeatherOperation]? = nil,
        sports: [SportsOperation]? = nil,
        time: [TimeOperation]? = nil,
        responseLength: SearchResponseLength? = nil
    ) {
        self.searchQuery = searchQuery
        self.imageQuery = imageQuery
        self.open = open
        self.click = click
        self.find = find
        self.screenshot = screenshot
        self.finance = finance
        self.weather = weather
        self.sports = sports
        self.time = time
        self.responseLength = responseLength
    }
}

extension SearchCommands: Codable {
    private enum CodingKeys: String, CodingKey {
        case searchQuery = "search_query"
        case imageQuery = "image_query"
        case open, click, find, screenshot, finance, weather, sports, time
        case responseLength = "response_length"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchQuery = try container.decodeIfPresent([SearchQuery].self, forKey: .searchQuery)
        imageQuery = try container.decodeIfPresent([SearchQuery].self, forKey: .imageQuery)
        open = try container.decodeIfPresent([OpenOperation].self, forKey: .open)
        click = try container.decodeIfPresent([ClickOperation].self, forKey: .click)
        find = try container.decodeIfPresent([FindOperation].self, forKey: .find)
        screenshot = try container.decodeIfPresent([ScreenshotOperation].self, forKey: .screenshot)
        finance = try container.decodeIfPresent([FinanceOperation].self, forKey: .finance)
        weather = try container.decodeIfPresent([WeatherOperation].self, forKey: .weather)
        sports = try container.decodeIfPresent([SportsOperation].self, forKey: .sports)
        time = try container.decodeIfPresent([TimeOperation].self, forKey: .time)
        responseLength = try container.decodeIfPresent(SearchResponseLength.self, forKey: .responseLength)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(searchQuery, forKey: .searchQuery)
        try container.encodeIfPresent(imageQuery, forKey: .imageQuery)
        try container.encodeIfPresent(open, forKey: .open)
        try container.encodeIfPresent(click, forKey: .click)
        try container.encodeIfPresent(find, forKey: .find)
        try container.encodeIfPresent(screenshot, forKey: .screenshot)
        try container.encodeIfPresent(finance, forKey: .finance)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encodeIfPresent(sports, forKey: .sports)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encodeIfPresent(responseLength, forKey: .responseLength)
    }
}

public struct SearchQuery: Codable, Equatable, Sendable {
    public var q: String
    public var recency: UInt64?
    public var domains: [String]?

    public init(q: String, recency: UInt64? = nil, domains: [String]? = nil) {
        self.q = q
        self.recency = recency
        self.domains = domains
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(q, forKey: .q)
        try container.encodeIfPresent(recency, forKey: .recency)
        try container.encodeIfPresent(domains, forKey: .domains)
    }
}

public struct OpenOperation: Codable, Equatable, Sendable {
    public var refId: String
    public var lineno: UInt64?

    public init(refId: String, lineno: UInt64? = nil) {
        self.refId = refId
        self.lineno = lineno
    }

    private enum CodingKeys: String, CodingKey {
        case refId = "ref_id"
        case lineno
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refId, forKey: .refId)
        try container.encodeIfPresent(lineno, forKey: .lineno)
    }
}

public struct ClickOperation: Codable, Equatable, Sendable {
    public var refId: String
    public var id: UInt64

    public init(refId: String, id: UInt64) {
        self.refId = refId
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case refId = "ref_id"
        case id
    }
}

public struct FindOperation: Codable, Equatable, Sendable {
    public var refId: String
    public var pattern: String

    public init(refId: String, pattern: String) {
        self.refId = refId
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey {
        case refId = "ref_id"
        case pattern
    }
}

public struct ScreenshotOperation: Codable, Equatable, Sendable {
    public var refId: String
    public var pageno: UInt64

    public init(refId: String, pageno: UInt64) {
        self.refId = refId
        self.pageno = pageno
    }

    private enum CodingKeys: String, CodingKey {
        case refId = "ref_id"
        case pageno
    }
}

public struct FinanceOperation: Codable, Equatable, Sendable {
    public var ticker: String
    public var type: FinanceAssetType
    public var market: String?

    public init(ticker: String, type: FinanceAssetType, market: String? = nil) {
        self.ticker = ticker
        self.type = type
        self.market = market
    }

    private enum CodingKeys: String, CodingKey {
        case ticker
        case type = "type"
        case market
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ticker, forKey: .ticker)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(market, forKey: .market)
    }
}

public enum FinanceAssetType: String, Codable, Equatable, Sendable {
    case equity
    case fund
    case crypto
    case index
}

public struct WeatherOperation: Codable, Equatable, Sendable {
    public var location: String
    public var start: String?
    public var duration: UInt64?

    public init(location: String, start: String? = nil, duration: UInt64? = nil) {
        self.location = location
        self.start = start
        self.duration = duration
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(duration, forKey: .duration)
    }
}

public struct SportsOperation: Codable, Equatable, Sendable {
    public var tool: SportsToolName?
    public var function: SportsFunction
    public var league: SportsLeague
    public var team: String?
    public var opponent: String?
    public var dateFrom: String?
    public var dateTo: String?
    public var numGames: UInt64?
    public var locale: String?

    public init(
        tool: SportsToolName? = nil,
        function: SportsFunction,
        league: SportsLeague,
        team: String? = nil,
        opponent: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        numGames: UInt64? = nil,
        locale: String? = nil
    ) {
        self.tool = tool
        self.function = function
        self.league = league
        self.team = team
        self.opponent = opponent
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.numGames = numGames
        self.locale = locale
    }

    private enum CodingKeys: String, CodingKey {
        case tool
        case function = "fn"
        case league, team, opponent
        case dateFrom = "date_from"
        case dateTo = "date_to"
        case numGames = "num_games"
        case locale
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(tool, forKey: .tool)
        try container.encode(function, forKey: .function)
        try container.encode(league, forKey: .league)
        try container.encodeIfPresent(team, forKey: .team)
        try container.encodeIfPresent(opponent, forKey: .opponent)
        try container.encodeIfPresent(dateFrom, forKey: .dateFrom)
        try container.encodeIfPresent(dateTo, forKey: .dateTo)
        try container.encodeIfPresent(numGames, forKey: .numGames)
        try container.encodeIfPresent(locale, forKey: .locale)
    }
}

public enum SportsToolName: String, Codable, Equatable, Sendable {
    case sports
}

public enum SportsFunction: String, Codable, Equatable, Sendable {
    case schedule
    case standings
}

public enum SportsLeague: String, Codable, Equatable, Sendable {
    case nba
    case wnba
    case nfl
    case nhl
    case mlb
    case epl
    case ncaamb
    case ncaawb
    case ipl
}

public struct TimeOperation: Codable, Equatable, Sendable {
    public var utcOffset: String

    public init(utcOffset: String) {
        self.utcOffset = utcOffset
    }

    private enum CodingKeys: String, CodingKey {
        case utcOffset = "utc_offset"
    }
}

public enum SearchResponseLength: String, Codable, Equatable, Sendable {
    case short
    case medium
    case long
}

public enum ExternalWebAccessMode: String, Codable, Equatable, Sendable {
    case cached
    case indexed
    case live
}

public enum ExternalWebAccess: Equatable, Sendable {
    case boolean(Bool)
    case mode(ExternalWebAccessMode)
}

extension ExternalWebAccess: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else {
            self = .mode(try container.decode(ExternalWebAccessMode.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .mode(let mode):
            try container.encode(mode)
        }
    }
}

public struct SearchSettings: Equatable, Sendable {
    public var userLocation: ApproximateLocation?
    public var searchContextSize: SearchContextSize?
    public var filters: SearchFilters?
    public var imageSettings: SearchImageSettings?
    public var allowedCallers: [AllowedCaller]?
    public var externalWebAccess: ExternalWebAccess?

    public init(
        userLocation: ApproximateLocation? = nil,
        searchContextSize: SearchContextSize? = nil,
        filters: SearchFilters? = nil,
        imageSettings: SearchImageSettings? = nil,
        allowedCallers: [AllowedCaller]? = nil,
        externalWebAccess: ExternalWebAccess? = nil
    ) {
        self.userLocation = userLocation
        self.searchContextSize = searchContextSize
        self.filters = filters
        self.imageSettings = imageSettings
        self.allowedCallers = allowedCallers
        self.externalWebAccess = externalWebAccess
    }
}

extension SearchSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case userLocation = "user_location"
        case searchContextSize = "search_context_size"
        case filters
        case imageSettings = "image_settings"
        case allowedCallers = "allowed_callers"
        case externalWebAccess = "external_web_access"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userLocation = try container.decodeIfPresent(ApproximateLocation.self, forKey: .userLocation)
        searchContextSize = try container.decodeIfPresent(SearchContextSize.self, forKey: .searchContextSize)
        filters = try container.decodeIfPresent(SearchFilters.self, forKey: .filters)
        imageSettings = try container.decodeIfPresent(SearchImageSettings.self, forKey: .imageSettings)
        allowedCallers = try container.decodeIfPresent([AllowedCaller].self, forKey: .allowedCallers)
        externalWebAccess = try container.decodeIfPresent(ExternalWebAccess.self, forKey: .externalWebAccess)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(userLocation, forKey: .userLocation)
        try container.encodeIfPresent(searchContextSize, forKey: .searchContextSize)
        try container.encodeIfPresent(filters, forKey: .filters)
        try container.encodeIfPresent(imageSettings, forKey: .imageSettings)
        try container.encodeIfPresent(allowedCallers, forKey: .allowedCallers)
        try container.encodeIfPresent(externalWebAccess, forKey: .externalWebAccess)
    }
}

public struct ApproximateLocation: Codable, Equatable, Sendable {
    public var type: LocationType
    public var country: String?
    public var region: String?
    public var city: String?
    public var timezone: String?

    public init(
        type: LocationType,
        country: String? = nil,
        region: String? = nil,
        city: String? = nil,
        timezone: String? = nil
    ) {
        self.type = type
        self.country = country
        self.region = region
        self.city = city
        self.timezone = timezone
    }

    private enum CodingKeys: String, CodingKey {
        case type = "type"
        case country, region, city, timezone
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(timezone, forKey: .timezone)
    }
}

public enum LocationType: String, Codable, Equatable, Sendable {
    case approximate
}

public enum SearchContextSize: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct SearchFilters: Codable, Equatable, Sendable {
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?

    public init(allowedDomains: [String]? = nil, blockedDomains: [String]? = nil) {
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
    }

    private enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
        case blockedDomains = "blocked_domains"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(allowedDomains, forKey: .allowedDomains)
        try container.encodeIfPresent(blockedDomains, forKey: .blockedDomains)
    }
}

public struct SearchImageSettings: Codable, Equatable, Sendable {
    public var maxResults: UInt64?
    public var caption: Bool?

    public init(maxResults: UInt64? = nil, caption: Bool? = nil) {
        self.maxResults = maxResults
        self.caption = caption
    }

    private enum CodingKeys: String, CodingKey {
        case maxResults = "max_results"
        case caption
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(maxResults, forKey: .maxResults)
        try container.encodeIfPresent(caption, forKey: .caption)
    }
}

public enum AllowedCaller: String, Codable, Equatable, Sendable {
    case direct
    case shell
    case codeInterpreter = "code_interpreter"
}

public struct SearchResponse: Equatable, Sendable {
    public var encryptedOutput: String?
    public var output: String
    public var results: [JSONValue]?

    public init(encryptedOutput: String?, output: String, results: [JSONValue]? = nil) {
        self.encryptedOutput = encryptedOutput
        self.output = output
        self.results = results
    }
}

extension SearchResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case encryptedOutput = "encrypted_output"
        case output, results
    }
}
