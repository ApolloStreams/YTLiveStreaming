import Foundation

extension Date {
   func toLocalTime() -> Date {
      let timeZone = TimeZone.autoupdatingCurrent
      let seconds: TimeInterval = Double(timeZone.secondsFromGMT(for: self))
      let localDate = Date(timeInterval: seconds, since: self)
      return localDate
   }

   func isGreaterThanDate(_ dateToCompare: Date) -> Bool {
      return self.compare(dateToCompare) == ComparisonResult.orderedDescending
   }

   func isLessThanDate(_ dateToCompare: Date) -> Bool {
      return self.compare(dateToCompare) == ComparisonResult.orderedAscending
   }

   func toJSONformat() -> String {
      let dateFormatterDate = DateFormatter()
      dateFormatterDate.dateFormat = "yyyy-MM-dd HH:mm:ss"
      let dateStr = dateFormatterDate.string(from: self)
      let startDateStr = String(dateStr.map {
         $0 == " " ? "T" : $0
         })
      let timeZone: TimeZone = TimeZone.autoupdatingCurrent
      let gmth = timeZone.secondsFromGMT(for: self) / 3600
      let gmtm = (timeZone.secondsFromGMT(for: self) % 3600)/60

      var hour: String = String(format: "+%02d", gmth)
      if gmth < 0 {
        hour = String(format: "%03d", gmth)
      }

      let startDate = startDateStr + hour + ":" +  String(format: "%02d", gmtm)
      return startDate
   }
}

func convertJSONtoDate(date: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.sssZ"
    return formatter.date(from: date)
}
