import SwiftUI

/// A planned trip.
public struct Trip: Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var symbol: String
    public var color: Color
    public var departure: Date
    public var nights: Int

    public init(name: String, symbol: String, color: Color, departure: Date, nights: Int) {
        self.name = name
        self.symbol = symbol
        self.color = color
        self.departure = departure
        self.nights = nights
    }
}

/// One trip in a list.
public struct TripRow: View {
    public var trip: Trip

    public init(trip: Trip) {
        self.trip = trip
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(trip.color.gradient, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading) {
                Text(trip.name).font(.headline)
                Text(trip.departure.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(trip.nights) nights").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Upcoming trips, soonest first.
public struct TripList: View {
    public var trips: [Trip]

    public init(trips: [Trip]) {
        self.trips = trips
    }

    public var body: some View {
        NavigationStack {
            List(trips) { trip in
                TripRow(trip: trip)
            }
            .navigationTitle("Upcoming")
        }
    }
}

extension Trip {
    /// Sample trips with fixed dates, so renders don't change from day to day.
    public static let samples: [Trip] = [
        Trip(
            name: "Kyoto", symbol: "building.columns.fill", color: .red,
            departure: Date(timeIntervalSince1970: 1_793_000_000), nights: 6),
        Trip(
            name: "Reykjavík", symbol: "snowflake", color: .cyan,
            departure: Date(timeIntervalSince1970: 1_795_600_000), nights: 4),
        Trip(
            name: "Lisbon", symbol: "sun.max.fill", color: .orange,
            departure: Date(timeIntervalSince1970: 1_798_200_000), nights: 5),
        Trip(
            name: "Patagonia", symbol: "mountain.2.fill", color: .green,
            departure: Date(timeIntervalSince1970: 1_801_000_000), nights: 10),
    ]
}

#Preview("Upcoming trips") {
    TripList(trips: Trip.samples)
}
