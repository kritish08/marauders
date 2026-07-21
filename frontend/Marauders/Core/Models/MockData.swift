import Foundation

enum MockData {
    static let bookings: [TourBooking] = [
        TourBooking(
            id: "booking-taj", packageID: "taj_mahal", name: "Taj Mahal",
            city: "Agra, Uttar Pradesh",
            imageName: "TajMahalMap"
        ),
        TourBooking(
            id: "booking-war", packageID: "national_war_memorial", name: "National War Memorial",
            city: "New Delhi",
            imageName: "WarMemorialMap"
        ),
        TourBooking(
            id: "booking-farm", packageID: "zomato_farmhouse", name: "Zomato Farmhouse",
            city: "Gurugram, Haryana",
            imageName: "ZomatoFarmMap"
        )
    ]
}
