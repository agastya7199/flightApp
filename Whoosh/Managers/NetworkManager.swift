//
//  NetworkManager.swift
//  Whoosh
//
//  Created by Shubh.
//

import Foundation
import Combine

enum Endpoint: String {
    case flights = "flights.json"
    case details = "flightDetails.json"
}

class NetworkManager {
    
    static let shared = NetworkManager()
    
    private init() {
        
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let baseURL = "https://raw.githubusercontent.com/agastya7199/flightApp/refs/heads/main/"

    /// true  = read flights.json / details.json bundled in the app (no server needed)
    /// false = call the local server at baseURL
    private let useMockData = false

    func getData<T: Decodable & Identifiable>(endpoint: Endpoint, id: Int? = nil, type: T.Type) -> Future<[T], Error> where T.ID == Int {
        if useMockData {
            return getMockData(endpoint: endpoint, id: id, type: type)
        }
        return getRemoteData(endpoint: endpoint, id: id, type: type)
    }

    /// Loads "<endpoint>.json" from the app bundle, e.g. flights.json or details.json.
    /// When an id is passed, only the item with that id is returned (like GET /details/1).
    private func getMockData<T: Decodable & Identifiable>(endpoint: Endpoint, id: Int?, type: T.Type) -> Future<[T], Error> where T.ID == Int {
        return Future<[T], Error> { promise in
            guard let url = Bundle.main.url(forResource: endpoint.rawValue, withExtension: "json") else {
                return promise(.failure(NetworkError.mockFileNotFound(endpoint.rawValue)))
            }
            do {
                let data = try Data(contentsOf: url)
                var items = try JSONDecoder().decode([T].self, from: data)
                if let id = id {
                    items = items.filter { $0.id == id }
                }
                // Return on the main thread with a short delay so the UI behaves like a real network call
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    promise(.success(items))
                }
            } catch {
                promise(.failure(error))
            }
        }
    }

    private func getRemoteData<T: Decodable>(endpoint: Endpoint, id: Int? = nil, type: T.Type) -> Future<[T], Error> {
        return Future<[T], Error> { [weak self] promise in
            guard let self = self, let url = URL(string: self.baseURL.appending(endpoint.rawValue)) else {
                return promise(.failure(NetworkError.invalidURL))
            }
            print("URL is \(url.absoluteString)")
            URLSession.shared.dataTaskPublisher(for: url)
                .tryMap { (data, response) -> Data in
                    guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                        throw NetworkError.responseError
                    }
                    return data
                }
                .decode(type: [T].self, decoder: JSONDecoder())
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { (completion) in
                    if case let .failure(error) = completion {
                        switch error {
                        case let decodingError as DecodingError:
                            promise(.failure(decodingError))
                        case let apiError as NetworkError:
                            promise(.failure(apiError))
                        default:
                            promise(.failure(NetworkError.unknown))
                        }
                    }
                }, receiveValue: { promise(.success($0)) })
                .store(in: &self.cancellables)
        }
    }
}


enum NetworkError: Error {
    case invalidURL
    case responseError
    case unknown
    case mockFileNotFound(String)
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid URL", comment: "Invalid URL")
        case .responseError:
            return NSLocalizedString("Unexpected status code", comment: "Invalid response")
        case .unknown:
            return NSLocalizedString("Unknown error", comment: "Unknown error")
        case .mockFileNotFound(let name):
            return "\(name).json not found in the app bundle. Check its Target Membership in Xcode."
        }
    }
}
