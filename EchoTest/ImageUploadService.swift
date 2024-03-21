import UIKit

class ImageUploadService {
    func uploadImage(_ image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "") else {
            completion(.failure(ImageUploadError.invalidURL))
            return
        }
        
        DispatchQueue.global().async {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                DispatchQueue.main.async {
                    completion(.failure(ImageUploadError.invalidImageData))
                }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.httpBody = imageData
            
            let session = URLSession.shared
            let task = session.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        DispatchQueue.main.async {
                            completion(.success("Image uploaded successfully"))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(ImageUploadError.serverError(httpResponse.statusCode)))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(ImageUploadError.invalidResponse))
                    }
                }
            }
            
            task.resume()
        }
    }
}

enum ImageUploadError: Error {
    case invalidURL
    case invalidImageData
    case serverError(Int)
    case invalidResponse
}
