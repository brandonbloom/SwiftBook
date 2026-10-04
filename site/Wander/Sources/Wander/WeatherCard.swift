import SwiftUI

/// Today's weather in one city.
public struct WeatherCard: View {
    public var city: String
    public var temperature: Int
    public var condition: String
    public var symbol: String
    public var high: Int
    public var low: Int

    public init(
        city: String, temperature: Int, condition: String, symbol: String, high: Int, low: Int
    ) {
        self.city = city
        self.temperature = temperature
        self.condition = condition
        self.symbol = symbol
        self.high = high
        self.low = low
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(city).font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.title2)
            }
            Text("\(temperature)°")
                .font(.system(size: 56, weight: .thin, design: .rounded))
            Text(condition).font(.headline)
            Text("H:\(high)°  L:\(low)°").font(.subheadline).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: 280)
        .background(
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.45, green: 0.3, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 24))
    }
}

#Preview("Weather card", traits: .sizeThatFitsLayout) {
    WeatherCard(
        city: "Cupertino", temperature: 72, condition: "Mostly Sunny", symbol: "cloud.sun.fill",
        high: 78, low: 58
    )
    .padding()
}
