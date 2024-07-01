//
//  YTLiveRequest.swift
//  YTLiveStreaming
//
//  Created by Serhii Krotkykh on 10/24/16.
//  Copyright © 2016 Serhii Krotkykh. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON
import Moya

class YTLiveRequest: NSObject {
  // Set up broadcast on your Youtube account:
  // https://www.youtube.com/my_live_events
  // https://www.youtube.com/live_dashboard
  // Errors:
  // https://support.google.com/youtube/answer/3006768?hl=ru
  
  // Developer console
  // https://console.developers.google.com/apis/credentials/key/0?project=fightnights-143711
}

// MARK: LiveBroatcasts requests
// https://developers.google.com/youtube/v3/live/docs/liveBroadcasts

extension YTLiveRequest {
  
  class func getHeaders() async throws -> HTTPHeaders {
    return await withCheckedContinuation { continuation in
      GoogleOAuth2.sharedInstance.requestToken { token in
        if let token = token {
          var headers: HTTPHeaders = [.contentType("application/json")]
          headers.add(.accept("application/json"))
          headers.add(.authorization("Bearer \(token)"))
          continuation.resume(returning: headers)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }
  
  class func listBroadcasts(_ status: YTLiveVideoState) async throws -> LiveBroadcastListModel {
    let parameters: [String: AnyObject] = [
      "part": "id,snippet,contentDetails,status" as AnyObject,
      "broadcastStatus": status.rawValue as AnyObject,
      "maxResults": LiveRequest.MaxResultObjects as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    do {
      let response = try await youTubeLiveVideoProvider.request(LiveStreamingAPI.listBroadcasts(parameters))
      let decoder = JSONDecoder()
      let liveBroadcastList = try decoder.decode(LiveBroadcastListModel.self, from: response.data)
      let totalResults = liveBroadcastList.pageInfo.totalResults
      let resultsPerPage = liveBroadcastList.pageInfo.resultsPerPage
      
      print("Broadcasts total count = \(totalResults)")
      
      if totalResults > resultsPerPage {
        // TODO: In this case you should send request
        // with pageToken=nextPageToken or pageToken=prevPageToken parameter
        print("Need to read next page!")
      }
      
      return liveBroadcastList
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  
  class func getLiveBroadcast(broadcastId: String) async throws -> LiveBroadcastStreamModel {
    let parameters: [String: AnyObject] = [
      "part": "id,snippet,contentDetails,status" as AnyObject,
      "id": broadcastId as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    do {
      let response = try await youTubeLiveVideoProvider.request(LiveStreamingAPI.liveBroadcast(parameters))
      let json = try JSON(data: response.data)
      let error = json["error"]
      let message = error["message"].stringValue
      
      if !message.isEmpty {
        throw YTError.message("Error while request broadcast list: " + message)
      } else {
        let decoder = JSONDecoder()
        let broadcastList = try decoder.decode(LiveBroadcastListModel.self, from: response.data)
        let items = broadcastList.items
        if let broadcast = items.first(where: { $0.id == broadcastId }) {
          return broadcast
        } else {
          throw YTError.message("broadcast does not exist")
        }
      }
    } catch {
      if let moyaError = error as? MoyaError {
        let code = moyaError.errorCode
        let message = moyaError.errorDescription ?? moyaError.localizedDescription
        throw YTError.systemMessage(code, message)
      } else {
        let message = "Parsing data error: \(error.localizedDescription)"
        throw YTError.message(message)
      }
    }
  }
  
  // https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/insert
  // Creates a broadcast.
  
  class func createLiveBroadcast(_ title: String,
                                 _ description: String,
                                 startDateTime: Date,
                                 privacy: String?,
                                 enableAutoStop: Bool?) async throws -> LiveBroadcastStreamModel {
    
    guard let headers = await getHeaders() else {
      throw YTError.message("OAuth token is not presented")
    }
    
    let jsonBody = CreateLiveBroadcastBody(title: title, description: description, startDateTime: startDateTime, privacy: privacy, enableAutoStop: enableAutoStop)
    
    guard let jsonData = try? JSONEncoder().encode(jsonBody),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
      throw YTError.message("Failed while preparing request")
    }
    
    let encoder = JSONBodyStringEncoding(jsonBody: jsonString)
    let parameters = "liveBroadcasts?part=id,snippet,contentDetails,status&key=\(Credentials.APIkey)"
    let url = "\(LiveAPI.BaseURL)/\(parameters)"
    
    let data = try await withCheckedThrowingContinuation { continuation in
      AF.request(url, method: .post, parameters: [:], encoding: encoder, headers: headers)
        .validate()
        .responseData { response in
          switch response.result {
          case .success(let data):
            continuation.resume(returning: data)
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }.cURLDescription { description in
          print("\n====== REQUEST =======\n\(description)\n==============\n")
        }
    }
    
    do {
      let json = try JSON(data: data)
      let error = json["error"].stringValue
      if !error.isEmpty {
        let message = json["message"].stringValue
        throw YTError.message("Error while Youtube broadcast was creating: \(message)")
      } else {
        let decoder = JSONDecoder()
        let liveBroadcast = try decoder.decode(LiveBroadcastStreamModel.self, from: data)
        return liveBroadcast
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  
  // Updates a broadcast. For example, you could modify the broadcast settings defined
  // in the liveBroadcast resource's contentDetails object.
  // https://developers.google.com/youtube/v3/live/docs/liveBroadcasts/update
  // PUT https://www.googleapis.com/youtube/v3/liveBroadcasts
  
  class func updateLiveBroadcast(_ broadcast: LiveBroadcastStreamModel) async throws {
    guard let headers = await getHeaders() else {
      throw YTError.message("OAuth token is not presented")
    }
    
    let jsonBody = UpdateLiveBroadcastBody(broadcast: broadcast)
    
    guard let jsonData = try? JSONEncoder().encode(jsonBody),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
      throw YTError.message("Failed while preparing request")
    }
    
    let encoder = JSONBodyStringEncoding(jsonBody: jsonString)
    let parameters = "liveBroadcasts?part=id,snippet,contentDetails,status&key=\(Credentials.APIkey)"
    
    let data = try await withCheckedThrowingContinuation { continuation in
      AF.request("\(LiveAPI.BaseURL)/\(parameters)",
                 method: .put,
                 parameters: [:],
                 encoding: encoder,
                 headers: headers)
      .responseData { response in
        switch response.result {
        case .success(let data):
          continuation.resume(returning: data)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }.cURLDescription { description in
        print("\n====== REQUEST =======\n\(description)\n==============\n")
      }
    }
    
    do {
      let json = try JSON(data: data)
      let error = json["error"].stringValue
      if !error.isEmpty {
        let message = json["message"].stringValue
        throw YTError.message("Error while Youtube broadcast was updating: " + message)
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  
  // POST https://www.googleapis.com/youtube/v3/liveBroadcasts/transition
  // Changes the status of a YouTube live broadcast and initiates any processes associated with the new status.
  // For example, when you transition a broadcast's status to testing, YouTube starts to transmit video
  // to that broadcast's monitor stream. Before calling this method, you should confirm that the value of the
  // status.streamStatus property for the stream bound to your broadcast is active.
  
  class func transitionLiveBroadcast(_ broadcastId: String,
                                     broadcastStatus: String) async throws -> LiveBroadcastStreamModel {
    
    let parameters: [String: AnyObject] = [
      "id": broadcastId as AnyObject,
      "broadcastStatus": broadcastStatus as AnyObject,
      "part": "id,snippet,contentDetails,status" as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    let response = try await withCheckedThrowingContinuation { continuation in
      youTubeLiveVideoProvider.request(LiveStreamingAPI.transitionLiveBroadcast(parameters)) { result in
        switch result {
        case let .success(response):
          continuation.resume(returning: response)
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
    
    do {
      let json = try JSON(data: response.data)
      let error = json["error"]
      let message = error["message"].stringValue
      if !message.isEmpty {
        let text = "FAILED TRANSITION TO THE \(broadcastStatus) STATUS [\(message)]!"
        throw YTError.message(text)
      } else {
        let decoder = JSONDecoder()
        let liveBroadcast = try decoder.decode(LiveBroadcastStreamModel.self, from: response.data)
        return liveBroadcast
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  
  // Deletes a broadcast.
  // DELETE https://www.googleapis.com/youtube/v3/liveBroadcasts
  
  class func deleteLiveBroadcast(broadcastId: String) async throws {
    let parameters: [String: AnyObject] = [
      "id": broadcastId as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    let response = try await withCheckedThrowingContinuation { continuation in
      youTubeLiveVideoProvider.request(LiveStreamingAPI.deleteLiveBroadcast(parameters)) { result in
        switch result {
        case let .success(response):
          continuation.resume(returning: response)
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
    
    do {
      let json = try JSON(data: response.data)
      let error = LiveBroadcastErrorModel.decode(json["error"])
      if let code = error.code, code > 0 {
        throw YTError.message("Failed of deleting broadcast: " + error.message!)
      } else {
        // print("Broadcast deleted: \(json)")
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  
  // Binds a YouTube broadcast to a stream or removes an existing binding between a broadcast and a stream.
  // A broadcast can only be bound to one video stream, though a video stream may be bound to more than one broadcast.
  // POST https://www.googleapis.com/youtube/v3/liveBroadcasts/bind
  
  class func bindLiveBroadcast(broadcastId: String, liveStreamId streamId: String) async throws -> LiveBroadcastStreamModel {
    let parameters: [String: AnyObject] = [
      "id": broadcastId as AnyObject,
      "streamId": streamId as AnyObject,
      "part": "id,snippet,contentDetails,status" as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    let response = try await withCheckedThrowingContinuation { continuation in
      youTubeLiveVideoProvider.request(LiveStreamingAPI.bindLiveBroadcast(parameters)) { result in
        switch result {
        case let .success(response):
          continuation.resume(returning: response)
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
    
    do {
      let json = try JSON(data: response.data)
      let error = json["error"]
      let message = error["message"].stringValue
      if !message.isEmpty {
        throw YTError.message("Error while Youtube broadcast binding with live stream: \(message)")
      } else {
        let decoder = JSONDecoder()
        let liveBroadcast = try decoder.decode(LiveBroadcastStreamModel.self, from: response.data)
        return liveBroadcast
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
}

// MARK: LiveStreams requests
// https://developers.google.com/youtube/v3/live/docs/liveStreams
// A liveStream resource contains information about the video stream that you are transmitting to YouTube.
// The stream provides the content that will be broadcast to YouTube users.
// Once created, a liveStream resource can be bound to one or more liveBroadcast resources.
extension YTLiveRequest {
  // Returns a list of video streams that match the API request parameters.
  // https://developers.google.com/youtube/v3/live/docs/liveStreams/list
  
  class func getLiveStream(_ liveStreamId: String) async throws -> LiveStreamModel {
    let parameters: [String: AnyObject] = [
      "part": "id,snippet,cdn,status" as AnyObject,
      "id": liveStreamId as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    let response = try await withCheckedThrowingContinuation { continuation in
      youTubeLiveVideoProvider.request(LiveStreamingAPI.liveStream(parameters)) { result in
        switch result {
        case let .success(response):
          continuation.resume(returning: response)
        case let .failure(error):
          continuation.resume(throwing: error)
        }
      }
    }
    
    do {
      let json = try JSON(data: response.data)
      let error = json["error"]
      let message = error["message"].stringValue
      if !message.isEmpty {
        throw YTError.message("Error while retrieving live stream: \(message)")
      } else {
        let broadcastList = LiveStreamListModel.decode(json)
        let items = broadcastList.items
        if let liveStream = items.first(where: { $0.id == liveStreamId }) {
          return liveStream
        } else {
          throw YTError.message("Live stream not found")
        }
      }
    } catch {
      let message = "Parsing data error: \(error.localizedDescription)"
      throw YTError.message(message)
    }
  }
  // https://developers.google.com/youtube/v3/live/docs/liveStreams/insert
  // Creates a video stream. The stream enables you to send your video to YouTube,
  // which can then broadcast the video to your audience.
  //   POST https://www.googleapis.com/youtube/v3/liveStreams?part=id%2Csnippet%2Ccdn%2Cstatus&key={YOUR_API_KEY}
  class func createLiveStream(_ title: String,
                              description: String,
                              streamName: String) async throws -> LiveStreamModel {
    // Get headers asynchronously
    guard let headers = try await getHeaders() else {
      throw YTError.message("OAuth token is not presented")
    }
    
    // Prepare JSON body
    let jsonBody = CreateLiveStreamBody(title: title, description: description, streamName: streamName)
    guard let jsonData = try? JSONEncoder().encode(jsonBody),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
      throw YTError.message("Failed while preparing request")
    }
    let encoder = JSONBodyStringEncoding(jsonBody: jsonString)
    
    // Construct URL and make the request
    let url = "\(LiveAPI.BaseURL)/liveStreams?part=id,snippet,cdn,status&key=\(Credentials.APIkey)"
    let (data, response) = try await AF.request(url, method: .post, parameters: [:], encoding: encoder, headers: headers)
      .validate()
      .responseData()
    
    // Handle response
    do {
      let json = try JSON(data: data)
      let error = json["error"]
      if !error.isEmpty {
        let message = json["message"].stringValue
        throw YTError.message("Error while Youtube broadcast was creating: \(message)")
      } else {
        return LiveStreamModel.decode(json)
      }
    } catch {
      if let statusCode = response?.statusCode {
        if let data = data {
          do {
            let json = try JSON(data: data)
            let errorMessage = json["error"]["message"].stringValue
            let errorType = json["error"]["errors"][0]["reason"].stringValue
            let apiError = "\(statusCode): \(errorType) - \(errorMessage)"
            throw YTError.apiError(statusCode, apiError)
          } catch {
            throw YTError.systemMessage(statusCode, error.localizedDescription)
          }
        } else {
          throw YTError.systemMessage(statusCode, error.localizedDescription)
        }
      } else {
        throw YTError.message("Failed to retrieve response")
      }
    }
  }
  
  // Deletes a video stream
  // Request:
  // DELETE https://www.googleapis.com/youtube/v3/liveStreams
  
  class func deleteLiveStream(_ liveStreamId: String) async throws {
    // Prepare parameters
    let parameters: [String: AnyObject] = [
      "id": liveStreamId as AnyObject,
      "key": Credentials.APIkey as AnyObject
    ]
    
    // Perform the request asynchronously
    let (data, response) = try await youTubeLiveVideoProvider.request(LiveStreamingAPI.deleteLiveStream(parameters))
    
    // Handle the response
    do {
      let json = try JSON(data: data)
      let error = json["error"].stringValue
      if !error.isEmpty {
        let message = json["message"].stringValue
        throw YTError.message(error + ";" + message)
      } else {
        print("video stream deleted: \(json)")
      }
    } catch {
      if let statusCode = response?.statusCode {
        if let data = data {
          do {
            let json = try JSON(data: data)
            let errorMessage = json["error"]["message"].stringValue
            let errorType = json["error"]["errors"][0]["reason"].stringValue
            let apiError = "\(statusCode): \(errorType) - \(errorMessage)"
            throw YTError.apiError(statusCode, apiError)
          } catch {
            throw YTError.systemMessage(statusCode, error.localizedDescription)
          }
        } else {
          throw YTError.systemMessage(statusCode, error.localizedDescription)
        }
      } else {
        throw YTError.message("Failed to retrieve response")
      }
    }
  }
  
  // Updates a video stream. If the properties that you want to change cannot be updated,
  // then you need to create a new stream with the proper settings.
  // Request:
  // PUT https://www.googleapis.com/youtube/v3/liveStreams
  // format = 1080p 1440p 240p 360p 480p 720p
  // ingestionType = dash rtmp
  class func updateLiveStream(_ liveStreamId: String,
                              title: String,
                              format: String,
                              ingestionType: String) async throws {
    // Get headers asynchronously
    guard let headers = try await getHeaders() else {
      throw YTError.message("OAuth token is not presented")
    }
    
    // Prepare JSON body
    let jsonBody = UpdateLiveStreamBody(id: liveStreamId, title: title, format: format, ingestionType: ingestionType)
    guard let jsonData = try? JSONEncoder().encode(jsonBody),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
      throw YTError.message("Failed while preparing request")
    }
    let encoder = JSONBodyStringEncoding(jsonBody: jsonString)
    
    // Perform the request asynchronously
    let url = "\(LiveAPI.BaseURL)/liveStreams"
    let (data, response) = try await AF.request(url,
                                                method: .put,
                                                parameters: ["part": "id,snippet,cdn,status", "key": Credentials.APIkey],
                                                encoding: encoder,
                                                headers: headers)
      .validate()
      .responseData()
    
    // Handle the response
    do {
      let json = try JSON(data: data)
      let error = json["error"].stringValue
      if !error.isEmpty {
        let message = json["message"].stringValue
        throw YTError.message("Error while Youtube broadcast was updating: " + message)
      }
    } catch {
      if let statusCode = response?.statusCode {
        if let data = data {
          do {
            let json = try JSON(data: data)
            let errorMessage = json["error"]["message"].stringValue
            let errorType = json["error"]["errors"][0]["reason"].stringValue
            let apiError = "\(statusCode): \(errorType) - \(errorMessage)"
            throw YTError.apiError(statusCode, apiError)
          } catch {
            throw YTError.systemMessage(statusCode, error.localizedDescription)
          }
        } else {
          throw YTError.systemMessage(statusCode, error.localizedDescription)
        }
      } else {
        throw YTError.message("Failed to retrieve response")
      }
    }
  }
}
