import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - API Models

struct ODSResponse: Decodable {
    let total_count: Int?
    let results: [RestaurantRecord]?
}

enum StringOrArray: Decodable, Hashable {
    case string(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)  { self = .string(s); return }
        if let a = try? c.decode([String].self) { self = .array(a);  return }
        self = .string("Activité inconnue")
    }

    var joined: String {
        switch self {
        case .string(let s): return s
        case .array(let a):  return a.joined(separator: ", ")
        }
    }
}

struct RestaurantRecord: Decodable, Identifiable, Hashable {
    var id = UUID()
    let app_libelle_etablissement: String?
    let app_libelle_activite_etablissement: StringOrArray?
    let adresse_2_ua: String?
    let code_postal: String?
    let libelle_commune: String?
    let synthese_eval_sanit: String?
    let date_inspection: String?
    let destination: String?
    let geores: GeoRes?

    enum CodingKeys: String, CodingKey {
        case app_libelle_etablissement, app_libelle_activite_etablissement
        case adresse_2_ua, code_postal, libelle_commune
        case synthese_eval_sanit, date_inspection, destination, geores
    }

    struct GeoRes: Decodable, Hashable {
        let lat: Double
        let lon: Double
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let g = geores else { return nil }
        return CLLocationCoordinate2D(latitude: g.lat, longitude: g.lon)
    }

    var hygieneLevel: HygieneLevel {
        let raw = synthese_eval_sanit?.lowercased() ?? ""
        if raw.contains("très") || raw.contains("tres") { return .tresSatisfaisant }
        if raw.contains("satisfai")                      { return .satisfaisant }
        if raw.contains("améliorer") || raw.contains("ameliorer") { return .aAmeliorer }
        if raw.contains("urgente")                       { return .urgence }
        return .inconnu
    }

    var formattedDate: String? {
        guard let dateString = date_inspection else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(dateString.prefix(10))) else { return dateString }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: d)
    }

    static func == (lhs: RestaurantRecord, rhs: RestaurantRecord) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum HygieneLevel: String, CaseIterable {
    case tresSatisfaisant = "Très satisfaisant"
    case satisfaisant     = "Satisfaisant"
    case aAmeliorer       = "À améliorer"
    case urgence          = "Urgence sanitaire"
    case inconnu          = "Inconnu"

    var color: Color {
        switch self {
        case .tresSatisfaisant: return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .satisfaisant:     return Color(red: 0.52, green: 0.80, blue: 0.09)
        case .aAmeliorer:       return .orange
        case .urgence:          return .red
        case .inconnu:          return Color(white: 0.6)
        }
    }

    var icon: String {
        switch self {
        case .tresSatisfaisant: return "checkmark.seal.fill"
        case .satisfaisant:     return "checkmark.circle.fill"
        case .aAmeliorer:       return "exclamationmark.triangle.fill"
        case .urgence:          return "xmark.octagon.fill"
        case .inconnu:          return "questionmark.circle.fill"
        }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    var onLocationFound: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onLocationFound = completion
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.onLocationFound?(loc.coordinate)
            self.onLocationFound = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Erreur de localisation: \(error)")
    }
}

// MARK: - ViewModel

@MainActor
class RestaurantViewModel: ObservableObject {
    @Published var restaurants:      [RestaurantRecord] = []
    @Published var searchResults:    [RestaurantRecord] = []
    @Published var searchQuery:      String  = ""
    @Published var isLoadingMap:     Bool    = false
    @Published var isSearching:      Bool    = false
    @Published var showZoomWarning:  Bool    = true
    @Published var errorMessage:     String? = nil
    @Published var hiddenLevels:     Set<HygieneLevel> = []
    @Published var selectedActivity: String = ""

    private let endpoint     = "https://dgal.opendatasoft.com/api/explore/v2.1/catalog/datasets/export_alimconfiance/records"
    private let selectFields = "app_libelle_etablissement,app_libelle_activite_etablissement,adresse_2_ua,code_postal,libelle_commune,synthese_eval_sanit,date_inspection,destination,geores"
    
    private var fetchTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    var visibleRestaurants: [RestaurantRecord] {
        restaurants.filter { r in
            !hiddenLevels.contains(r.hygieneLevel) &&
            (selectedActivity.isEmpty ||
             (r.destination?.lowercased().contains(selectedActivity.lowercased()) ?? false) ||
             (r.app_libelle_activite_etablissement?.joined.lowercased().contains(selectedActivity.lowercased()) ?? false))
        }
    }

    func triggerSearch() {
        searchTask?.cancel()
        
        guard searchQuery.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        
        searchTask = Task {
            isSearching = true
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            let q = searchQuery.replacingOccurrences(of: "\"", with: "")
            let qUpper = q.uppercased()
            
            // 🔥 LA CORRECTION EST ICI 🔥
            // Fini le "search()" flou qui donnait n'importe quoi.
            // Règle 1 : L'établissement COMMENCE EXACTEMENT par "BONNIE..." (like "BONNIE%")
            // Règle 2 : L'établissement contient un mot qui COMMENCE par "BONNIE..." (like "% BONNIE%")
            // Règle 3 : La ville COMMENCE EXACTEMENT par "BONNIE..."
            let clause = "app_libelle_etablissement like \"\(qUpper)*\" or libelle_commune like \"\(qUpper)%\""

            await performFetch(whereClause: clause, isGlobalSearch: true)
            
            if !Task.isCancelled {
                isSearching = false
            }
        }
    }

    func fetchMapData(region: MKCoordinateRegion) {
        fetchTask?.cancel()
        guard region.span.latitudeDelta <= 1.5 else { showZoomWarning = true; restaurants = []; return }
        showZoomWarning = false

        fetchTask = Task {
            defer { self.isLoadingMap = false }
            self.isLoadingMap = true; self.errorMessage = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let c = region.center, d = region.span
            let minLat = c.latitude  - d.latitudeDelta  / 2, maxLat = c.latitude  + d.latitudeDelta  / 2
            let minLon = c.longitude - d.longitudeDelta / 2, maxLon = c.longitude + d.longitudeDelta / 2

            var clauses = ["intersects(geores, geom'POLYGON((\(minLon) \(minLat),\(maxLon) \(minLat),\(maxLon) \(maxLat),\(minLon) \(maxLat),\(minLon) \(minLat)))')"]
            if !selectedActivity.isEmpty { clauses.append("destination like \"%\(selectedActivity)%\"") }
            await performFetch(whereClause: clauses.joined(separator: " and "), isGlobalSearch: false)
        }
    }

    private func performFetch(whereClause: String, isGlobalSearch: Bool) async {
        var comps = URLComponents(string: endpoint)!
        comps.queryItems = [
            URLQueryItem(name: "limit",    value: "100"),
            URLQueryItem(name: "where",    value: whereClause),
            URLQueryItem(name: "order_by", value: "date_inspection desc"),
            URLQueryItem(name: "select",   value: selectFields)
        ]
        guard let url = comps.url else { return }
        
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                self.errorMessage = "Erreur API (\(http.statusCode))"
                return
            }
            let decoded = try JSONDecoder().decode(ODSResponse.self, from: data)
            let valid = (decoded.results ?? []).filter { $0.coordinate != nil }
            if isGlobalSearch { self.searchResults = valid } else { self.restaurants = valid }
        } catch {
            guard !Task.isCancelled else { return }
            self.errorMessage = "Impossible de charger les données"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var viewModel       = RestaurantViewModel()
    @StateObject private var locationManager = LocationManager()

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.6, longitude: 1.9),
        span:   MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    ))
    @State private var selectedRestaurant: RestaurantRecord?
    @State private var showSheet  = true
    @State private var showPopup  = false
    
    @FocusState private var isSearchFocused: Bool

    let bottomSheetHeight: CGFloat = 230

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {

                // ── CARTE ──
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    ForEach(viewModel.visibleRestaurants) { r in
                        if let coord = r.coordinate {
                            Annotation("", coordinate: coord) {
                                MapPinView(color: r.hygieneLevel.color) {
                                    isSearchFocused = false
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        selectedRestaurant = r; showPopup = true
                                    }
                                }
                            }
                        }
                    }
                }
                .mapStyle(.imagery)
                .mapControls { MapCompass() }
                .safeAreaPadding(.bottom, bottomSheetHeight + 20)
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { ctx in viewModel.fetchMapData(region: ctx.region) }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isSearchFocused = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            showPopup = false
                        }
                    }
                )
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.triggerSearch()
                }
                
                // ── RECHERCHE ──
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("Rechercher un établissement...", text: $viewModel.searchQuery)
                            .focused($isSearchFocused)
                        if !viewModel.searchQuery.isEmpty {
                            Button {
                                viewModel.searchQuery = ""
                                viewModel.searchResults = []
                                isSearchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = true
                    }
                    .padding(.horizontal, 16).padding(.top, 10)

                    if !viewModel.searchQuery.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                if viewModel.isSearching {
                                    ProgressView().padding(.vertical, 20)
                                } else if viewModel.searchResults.isEmpty {
                                    Text("Aucun établissement à ce nom.")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 20)
                                } else {
                                    ForEach(viewModel.searchResults) { r in
                                        Button { focusOn(restaurant: r) } label: {
                                            HStack(spacing: 12) {
                                                Circle().fill(r.hygieneLevel.color).frame(width: 10, height: 10)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(r.app_libelle_etablissement ?? "Inconnu")
                                                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                                                    Text(r.libelle_commune ?? "").font(.caption).foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(Color(UIColor.systemBackground))
                                        }
                                        Divider().padding(.leading, 38)
                                    }
                                }
                            }
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                            .padding(.horizontal, 16)
                        }
                        .frame(maxHeight: geometry.size.height * 0.4)
                    }

                    if viewModel.showZoomWarning {
                        StatusPill(text: "🔍 Zoomez pour charger les données", background: Color.orange.opacity(0.92))
                    } else if viewModel.isLoadingMap {
                        StatusPill(text: "Chargement...", background: Color.black.opacity(0.7), spinner: true)
                    } else if let err = viewModel.errorMessage {
                        StatusPill(text: "⚠️ \(err)", background: Color.red.opacity(0.85))
                    }
                }

                // ── POPUP ──
                if showPopup, let r = selectedRestaurant {
                    VStack {
                        Spacer()
                        RestaurantPopupCard(restaurant: r) {
                            withAnimation(.easeOut(duration: 0.2)) { showPopup = false }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomSheetHeight + 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(10)
                    .allowsHitTesting(true)
                }

                // ── GÉOLOC ──
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            locationManager.requestLocation { loc in
                                let r = MKCoordinateRegion(center: loc, span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { cameraPosition = .region(r) }
                                viewModel.fetchMapData(region: r)
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 50, height: 50).background(Color.blue)
                                .clipShape(Circle()).shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, bottomSheetHeight + 20)
                    }
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            BottomSheetView(viewModel: viewModel)
                .presentationDetents([.height(200), .large])
                .presentationBackground(Color.white)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
                .presentationBackgroundInteraction(.enabled)
                .presentationCornerRadius(24)
        }
    }

    private func focusOn(restaurant: RestaurantRecord) {
        isSearchFocused = false
        viewModel.searchQuery = ""; viewModel.searchResults = []
        guard let coord = restaurant.coordinate else { return }
        cameraPosition = .region(.init(center: coord, span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedRestaurant = restaurant; showPopup = true }
    }
}

// MARK: - Bottom Sheet

struct BottomSheetView: View {
    @ObservedObject var viewModel: RestaurantViewModel

    let activities: [(label: String, value: String)] = [
        ("Toutes les activités",        ""),
        ("Restauration traditionnelle", "Restauration traditionnelle"),
        ("Restauration rapide",         "Restauration rapide"),
        ("Restauration collective",     "Restauration collective"),
        ("Boulangerie / Pâtisserie",    "Boulangerie"),
        ("Commerce de détail",          "Commerce de détail"),
        ("Supermarché / Hypermarché",   "Supermarché"),
    ]
    
    private var activeLevels: [HygieneLevel] { HygieneLevel.allCases.filter { $0 != .inconnu } }
    private var firstRow: [HygieneLevel] { Array(activeLevels.prefix((activeLevels.count + 1) / 2)) }
    private var secondRow: [HygieneLevel] { Array(activeLevels.dropFirst((activeLevels.count + 1) / 2)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.visibleRestaurants.count)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.blue)
                Text("résultats sur cette zone")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)

            SectionDivider(label: "Filtrage activité")

            HStack(spacing: 8) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 20)

                Picker("", selection: $viewModel.selectedActivity) {
                    ForEach(activities, id: \.value) { act in Text(act.label).tag(act.value) }
                }
                .pickerStyle(.menu)
                .tint(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

            SectionDivider(label: "Filtrage hygiène")

            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    ForEach(firstRow, id: \.self) { level in levelButton(for: level) }
                }
                HStack(spacing: 7) {
                    ForEach(secondRow, id: \.self) { level in levelButton(for: level) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Spacer(minLength: 0)
        }
    }
    
    @ViewBuilder
    private func levelButton(for level: HygieneLevel) -> some View {
        let isHidden = viewModel.hiddenLevels.contains(level)
        
        Button {
            if isHidden { viewModel.hiddenLevels.remove(level) }
            else        { viewModel.hiddenLevels.insert(level) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isHidden ? Color.secondary.opacity(0.3) : level.color)
                    .frame(width: 7, height: 7)
                Text(level.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isHidden ? Color(UIColor.systemGray5) : level.color.opacity(0.12))
            .foregroundColor(isHidden ? .secondary : level.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isHidden ? Color.clear : level.color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Divider

struct SectionDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(UIColor.systemGray4)).frame(height: 0.5)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(UIColor.systemGray2))
                .kerning(0.8)
                .fixedSize()
            Rectangle().fill(Color(UIColor.systemGray4)).frame(height: 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }
}

// MARK: - Restaurant Popup Card

struct RestaurantPopupCard: View {
    let restaurant: RestaurantRecord
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(restaurant.hygieneLevel.color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: restaurant.hygieneLevel.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(restaurant.hygieneLevel.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(restaurant.app_libelle_etablissement ?? "Inconnu")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.primary).lineLimit(2)
                    Text(restaurant.destination ?? restaurant.app_libelle_activite_etablissement?.joined ?? "Activité non précisée")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                        .frame(width: 28, height: 28).background(Color(UIColor.systemGray5)).clipShape(Circle())
                }
            }
            .padding(16)

            Divider()

            VStack(spacing: 0) {
                InfoRow(icon: restaurant.hygieneLevel.icon, iconColor: restaurant.hygieneLevel.color,
                        label: "Résultat", value: restaurant.synthese_eval_sanit ?? "Non renseigné",
                        valueColor: restaurant.hygieneLevel.color)
                Divider().padding(.leading, 44)
                InfoRow(icon: "calendar.badge.checkmark", iconColor: .blue,
                        label: "Dernier contrôle", value: restaurant.formattedDate ?? "Date inconnue")
                Divider().padding(.leading, 44)
                InfoRow(icon: "mappin.circle.fill", iconColor: .red, label: "Adresse",
                        value: [restaurant.adresse_2_ua, restaurant.code_postal, restaurant.libelle_commune]
                            .compactMap { $0 }.joined(separator: " "))
            }
            .padding(.vertical, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(restaurant.hygieneLevel.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}

struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium)).foregroundColor(iconColor)
                .frame(width: 32, height: 32).background(iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(.secondary).textCase(.uppercase).kerning(0.5)
                Text(value).font(.system(size: 14, weight: .medium)).foregroundColor(valueColor)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let text: String
    let background: Color
    var spinner: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().scaleEffect(0.75).tint(.white) }
            Text(text).font(.caption).bold()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(background).cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Map Pin

struct MapPinView: View {
    let color: Color
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(color).frame(width: 34, height: 34)
                    .shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 2)
                Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 34, height: 34)
                Image(systemName: "fork.knife").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            Triangle().fill(color).frame(width: 10, height: 7)
                .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .frame(width: 60, height: 60)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Splash Screen

struct SplashScreenView: View {
    @State private var isActive = false
    @State private var progress: CGFloat = 0.0

    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color.blue.ignoresSafeArea()

                VStack(spacing: 20) {
                    Image("image")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 150)
                        .shadow(radius: 10)
                    
                    Text("RESTAURANT CHECKER")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 200, height: 8)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: progress, height: 8)
                    }
                    .padding(.top, 40)
                    
                    Text("Chargement de la carte...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 5)
                }
                
                VStack {
                    Spacer()
                    
                    Text("DONNÉES OFFICIELLES DGAL Alim'Confiance")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(0.5)
                        .padding(.bottom, 30)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 5.0)) {
                    progress = 200.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
