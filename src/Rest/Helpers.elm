module Rest.Helpers exposing (openstackCredentialedRequest)

import Http
import Task
import Time
import Types.HelperTypes exposing (..)
import Types.OpenstackTypes as OSTypes
import Types.Types exposing (..)


httpRequestMethodStr : HttpRequestMethod -> String
httpRequestMethodStr method =
    case method of
        Get ->
            "GET"

        Post ->
            "POST"

        Delete ->
            "DELETE"


openstackCredentialedRequest : Provider -> HttpRequestMethod -> Url -> Http.Body -> Http.Expect a -> (Result Http.Error a -> Msg) -> Cmd Msg
openstackCredentialedRequest provider method url requestBody expect resultMsg =
    {-
       In order to ensure request is made with a valid token, perform a task
       which checks the time to see if our auth token is still valid or has
       expired. Pass along a function which accepts an auth token, and returns
       a "hydrated" Cmd Msg (which sends the request to OpenStack API).

    -}
    let
        tokenToRequestCmd : OSTypes.AuthTokenString -> Cmd Msg
        tokenToRequestCmd token =
            let
                request =
                    Http.request
                        { method = httpRequestMethodStr method
                        , headers = [ Http.header "X-Auth-Token" token ]
                        , url = url
                        , body = requestBody
                        , expect = expect
                        , timeout = Nothing
                        , withCredentials = False
                        }
            in
            Http.send resultMsg request
    in
    Task.perform
        (\posixTime -> ProviderMsg provider.name (ValidateTokenForCredentialedRequest tokenToRequestCmd posixTime))
        Time.now
