[![forthebadge](http://forthebadge.com/images/badges/made-with-swift.svg)](http://forthebadge.com)
[![forthebadge](http://forthebadge.com/images/badges/as-seen-on-tv.svg)](http://forthebadge.com)

# Perfect-Cache
Simple Perfect swift file caching

## Usage

```swift
let cache = PerfectCache()

func handler(data: [String:Any]) throws -> RequestHandler {
     return { request, response in
         response.setHeader(.contentType, value: "application/json")
         if cache.return(for: request, with: response) {
             return
         }

         // ... Do some stuff to build of the HTTPResponse
         cache.write(response: response, for: request)
         response.completed()
    }
}
 
let confData = [
    "servers": [
        [
            "name": "localhost",
            "port": 8080,
            "routes":[
                [ "method": "get", "uri": "/user/me", "handler": handler ]
            ],
            "filters": filters()
        ]
    ]
]

do {
    try HTTPServer.launch(configurationData: confData)
} catch {
    fatalError("\(error)")
}

```
