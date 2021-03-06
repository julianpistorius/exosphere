module Helpers.Helpers exposing
    ( checkFloatingIpState
    , flavorLookup
    , getExternalNetwork
    , getServerExouserPassword
    , getServerFloatingIp
    , getServerUiStatus
    , getServerUiStatusColor
    , getServerUiStatusStr
    , imageLookup
    , iso8601StringToPosix
    , modelUpdateProvider
    , newServerNetworkOptions
    , processError
    , processOpenRc
    , providePasswordHint
    , providerLookup
    , providerNameFromUrl
    , providerTitle
    , providerUpdateServer
    , serverLookup
    , serviceCatalogToEndpoints
    , sortedFlavors
    , stringIsUuidOrDefault
    , toastConfig
    )

import Debug
import Html
import Html.Attributes
import ISO8601
import Maybe.Extra
import Regex
import RemoteData
import Time
import Toasty
import Toasty.Defaults
import Types.HelperTypes as HelperTypes
import Types.OpenstackTypes as OSTypes
import Types.Types exposing (..)


alwaysRegex : String -> Regex.Regex
alwaysRegex regexStr =
    Regex.fromString regexStr |> Maybe.withDefault Regex.never


toastConfig : Toasty.Config Msg
toastConfig =
    let
        containerAttrs : List (Html.Attribute msg)
        containerAttrs =
            [ Html.Attributes.style "position" "fixed"
            , Html.Attributes.style "top" "60"
            , Html.Attributes.style "right" "0"
            , Html.Attributes.style "width" "100%"
            , Html.Attributes.style "max-width" "300px"
            , Html.Attributes.style "list-style-type" "none"
            , Html.Attributes.style "padding" "0"
            , Html.Attributes.style "margin" "0"
            ]
    in
    Toasty.Defaults.config
        |> Toasty.delay 60000
        |> Toasty.containerAttrs containerAttrs


processError : Model -> a -> ( Model, Cmd Msg )
processError model error =
    let
        errorString =
            Debug.toString error

        newMsgs =
            errorString :: model.messages

        newModel =
            { model | messages = newMsgs }

        toast =
            Toasty.Defaults.Error "Error" errorString
    in
    Toasty.addToastIfUnique toastConfig ToastyMsg toast ( newModel, Cmd.none )


stringIsUuidOrDefault : String -> Bool
stringIsUuidOrDefault str =
    -- We accept some login fields from user (e.g. Keystone domains) that could be a name or a UUID.
    -- Further, OpenStack treats "default" as a special case that can be passed in UUID fields.
    -- This function helps functions like Rest.requestAuthToken specify the right JSON field (name or ID).
    let
        stringIsUuid =
            let
                strNoHyphens =
                    String.filter (\c -> c /= '-') str

                isValidHex : Char -> Bool
                isValidHex c =
                    String.any (\h -> c == h) "0123456789abcdef"

                isValidLength =
                    String.length strNoHyphens == 32
            in
            String.all isValidHex strNoHyphens && isValidLength

        stringIsDefault =
            String.toLower str == "default"
    in
    stringIsUuid || stringIsDefault


processOpenRc : Creds -> String -> Creds
processOpenRc existingCreds openRc =
    let
        regexes =
            { authUrl = alwaysRegex "export OS_AUTH_URL=\"?([^\"\n]*)\"?"
            , projectDomain = alwaysRegex "export OS_PROJECT_DOMAIN(?:_NAME|_ID)=\"?([^\"\n]*)\"?"
            , projectName = alwaysRegex "export OS_PROJECT_NAME=\"?([^\"\n]*)\"?"
            , userDomain = alwaysRegex "export OS_USER_DOMAIN(?:_NAME|_ID)=\"?([^\"\n]*)\"?"
            , username = alwaysRegex "export OS_USERNAME=\"?([^\"\n]*)\"?"
            , password = alwaysRegex "export OS_PASSWORD=\"(.*)\""
            }

        getMatch text regex =
            Regex.findAtMost 1 regex text
                |> List.head
                |> Maybe.map (\x -> x.submatches)
                |> Maybe.andThen List.head
                |> Maybe.Extra.join

        newField regex oldField =
            getMatch openRc regex
                |> Maybe.withDefault oldField
    in
    Creds
        (newField regexes.authUrl existingCreds.authUrl)
        (newField regexes.projectDomain existingCreds.projectDomain)
        (newField regexes.projectName existingCreds.projectName)
        (newField regexes.userDomain existingCreds.userDomain)
        (newField regexes.username existingCreds.username)
        (newField regexes.password existingCreds.password)


providePasswordHint : String -> String -> List { styleKey : String, styleValue : String }
providePasswordHint username password =
    let
        checks =
            [ not <| String.isEmpty username
            , String.isEmpty password
            , username /= "demo"
            ]
    in
    if List.all (\p -> p) checks then
        [ { styleKey = "border-color", styleValue = "rgba(239, 130, 17, 0.8)" }
        , { styleKey = "background-color", styleValue = "rgba(245, 234, 234, 0.7)" }
        ]

    else
        []


providerTitle : ProviderName -> ProviderTitle
providerTitle providerName =
    let
        r =
            alwaysRegex "^(.*?)\\..*"

        matches =
            Regex.findAtMost 1 r providerName

        maybeMaybeTitle =
            matches
                |> List.head
                |> Maybe.map (\x -> x.submatches)
                |> Maybe.andThen List.head
    in
    case maybeMaybeTitle of
        Just (Just title) ->
            title

        _ ->
            providerName


providerNameFromUrl : HelperTypes.Url -> ProviderName
providerNameFromUrl url =
    let
        r =
            alwaysRegex ".*\\/\\/(.*?)(:\\d+)?\\/"

        matches =
            Regex.findAtMost 1 r url

        maybeMaybeName =
            matches
                |> List.head
                |> Maybe.map (\x -> x.submatches)
                |> Maybe.andThen List.head
    in
    case maybeMaybeName of
        Just (Just name) ->
            name

        _ ->
            "placeholder-url-unparseable"


iso8601StringToPosix : String -> Result String Time.Posix
iso8601StringToPosix str =
    ISO8601.fromString str
        |> Result.map ISO8601.toPosix


serviceCatalogToEndpoints : OSTypes.ServiceCatalog -> Endpoints
serviceCatalogToEndpoints catalog =
    Endpoints
        (getServicePublicUrl "glance" catalog)
        (getServicePublicUrl "nova" catalog)
        (getServicePublicUrl "neutron" catalog)


getServicePublicUrl : String -> OSTypes.ServiceCatalog -> HelperTypes.Url
getServicePublicUrl serviceName catalog =
    let
        maybeService =
            getServiceFromCatalog serviceName catalog

        maybePublicEndpoint =
            getPublicEndpointFromService maybeService
    in
    case maybePublicEndpoint of
        Just endpoint ->
            endpoint.url

        Nothing ->
            ""


getServiceFromCatalog : String -> OSTypes.ServiceCatalog -> Maybe OSTypes.Service
getServiceFromCatalog serviceName catalog =
    List.filter (\s -> s.name == serviceName) catalog
        |> List.head


getPublicEndpointFromService : Maybe OSTypes.Service -> Maybe OSTypes.Endpoint
getPublicEndpointFromService maybeService =
    case maybeService of
        Just service ->
            List.filter (\e -> e.interface == OSTypes.Public) service.endpoints
                |> List.head

        Nothing ->
            Nothing


getExternalNetwork : Provider -> Maybe OSTypes.Network
getExternalNetwork provider =
    List.filter (\n -> n.isExternal) provider.networks |> List.head


checkFloatingIpState : OSTypes.ServerDetails -> FloatingIpState -> FloatingIpState
checkFloatingIpState serverDetails floatingIpState =
    let
        hasFixedIp =
            List.filter (\a -> a.openstackType == OSTypes.IpAddressFixed) serverDetails.ipAddresses
                |> List.isEmpty
                |> not

        hasFloatingIp =
            List.filter (\a -> a.openstackType == OSTypes.IpAddressFloating) serverDetails.ipAddresses
                |> List.isEmpty
                |> not

        isActive =
            serverDetails.openstackStatus == OSTypes.ServerActive
    in
    case floatingIpState of
        RequestedWaiting ->
            if hasFloatingIp then
                Success

            else
                RequestedWaiting

        Failed ->
            Failed

        _ ->
            if hasFloatingIp then
                Success

            else if hasFixedIp && isActive then
                Requestable

            else
                NotRequestable


serverLookup : Provider -> OSTypes.ServerUuid -> Maybe Server
serverLookup provider serverUuid =
    List.filter (\s -> s.osProps.uuid == serverUuid) (RemoteData.withDefault [] provider.servers) |> List.head


providerLookup : Model -> ProviderName -> Maybe Provider
providerLookup model providerName =
    List.filter
        (\p -> p.name == providerName)
        model.providers
        |> List.head


flavorLookup : Provider -> OSTypes.FlavorUuid -> Maybe OSTypes.Flavor
flavorLookup provider flavorUuid =
    List.filter
        (\f -> f.uuid == flavorUuid)
        provider.flavors
        |> List.head


imageLookup : Provider -> OSTypes.ImageUuid -> Maybe OSTypes.Image
imageLookup provider imageUuid =
    List.filter
        (\i -> i.uuid == imageUuid)
        provider.images
        |> List.head


modelUpdateProvider : Model -> Provider -> Model
modelUpdateProvider model newProvider =
    let
        otherProviders =
            List.filter (\p -> p.name /= newProvider.name) model.providers

        newProviders =
            newProvider :: otherProviders

        newProvidersSorted =
            List.sortBy (\p -> p.name) newProviders
    in
    { model | providers = newProvidersSorted }


providerUpdateServer : Provider -> Server -> Provider
providerUpdateServer provider server =
    let
        otherServers =
            List.filter
                (\s -> s.osProps.uuid /= server.osProps.uuid)
                (RemoteData.withDefault [] provider.servers)

        newServers =
            server :: otherServers

        newServersSorted =
            List.sortBy (\s -> s.osProps.name) newServers
    in
    { provider | servers = RemoteData.Success newServersSorted }


getServerFloatingIp : List OSTypes.IpAddress -> Maybe String
getServerFloatingIp ipAddresses =
    let
        isFloating ipAddress =
            ipAddress.openstackType == OSTypes.IpAddressFloating
    in
    List.filter isFloating ipAddresses
        |> List.head
        |> Maybe.map .address


getServerExouserPassword : OSTypes.ServerDetails -> Maybe String
getServerExouserPassword serverDetails =
    List.filter (\i -> i.key == "exouserPassword") serverDetails.metadata
        |> List.head
        |> Maybe.map .value


getServerUiStatus : Server -> ServerUiStatus
getServerUiStatus server =
    case server.osProps.details of
        Nothing ->
            ServerUiStatusUnknown

        Just details ->
            case details.openstackStatus of
                OSTypes.ServerActive ->
                    case server.exoProps.cockpitStatus of
                        NotChecked ->
                            ServerUiStatusStarting

                        CheckedNotReady ->
                            ServerUiStatusStarting

                        Ready ->
                            ServerUiStatusReady

                OSTypes.ServerPaused ->
                    ServerUiStatusPaused

                OSTypes.ServerSuspended ->
                    ServerUiStatusSuspended

                OSTypes.ServerShutoff ->
                    ServerUiStatusShutoff

                OSTypes.ServerStopped ->
                    ServerUiStatusStopped

                OSTypes.ServerSoftDeleted ->
                    ServerUiStatusSoftDeleted

                OSTypes.ServerError ->
                    ServerUiStatusError

                OSTypes.ServerBuilding ->
                    ServerUiStatusBuilding

                OSTypes.ServerRescued ->
                    ServerUiStatusRescued

                OSTypes.ServerShelved ->
                    ServerUiStatusShelved

                OSTypes.ServerShelvedOffloaded ->
                    ServerUiStatusShelved


getServerUiStatusStr : ServerUiStatus -> String
getServerUiStatusStr status =
    case status of
        ServerUiStatusUnknown ->
            "Unknown"

        ServerUiStatusBuilding ->
            "Building"

        ServerUiStatusStarting ->
            "Starting"

        ServerUiStatusReady ->
            "Ready"

        ServerUiStatusPaused ->
            "Paused"

        ServerUiStatusSuspended ->
            "Suspended"

        ServerUiStatusShutoff ->
            "Shut off"

        ServerUiStatusStopped ->
            "Stopped"

        ServerUiStatusSoftDeleted ->
            "Soft-deleted"

        ServerUiStatusError ->
            "Error"

        ServerUiStatusRescued ->
            "Rescued"

        ServerUiStatusShelved ->
            "Shelved"


getServerUiStatusColor : ServerUiStatus -> String
getServerUiStatusColor status =
    case status of
        ServerUiStatusUnknown ->
            "gray"

        ServerUiStatusBuilding ->
            "yellow"

        ServerUiStatusStarting ->
            "yellow"

        ServerUiStatusReady ->
            "green"

        ServerUiStatusPaused ->
            "gray"

        ServerUiStatusSuspended ->
            "gray"

        ServerUiStatusShutoff ->
            "gray"

        ServerUiStatusStopped ->
            "gray"

        ServerUiStatusSoftDeleted ->
            "gray"

        ServerUiStatusError ->
            "red"

        ServerUiStatusRescued ->
            "red"

        ServerUiStatusShelved ->
            "gray"


sortedFlavors : List OSTypes.Flavor -> List OSTypes.Flavor
sortedFlavors flavors =
    flavors
        |> List.sortBy .disk_ephemeral
        |> List.sortBy .disk_root
        |> List.sortBy .ram_mb
        |> List.sortBy .vcpu


newServerNetworkOptions : Provider -> NewServerNetworkOptions
newServerNetworkOptions provider =
    {- When creating a new server, make a reasonable choice of project network, if we can. -}
    let
        -- First, filter on networks that are status ACTIVE, adminStateUp, and not external
        projectNets =
            provider.networks
                |> List.filter (\n -> n.status == "ACTIVE")
                |> List.filter (\n -> n.adminStateUp == True)
                |> List.filter (\n -> n.isExternal == False)

        maybeAutoAllocatedNet =
            projectNets
                |> List.filter (\n -> n.name == "auto_allocated_network")
                |> List.head

        maybeProjectNameNet =
            projectNets
                |> List.filter (\n -> String.contains provider.auth.projectName n.name)
                |> List.head
    in
    case projectNets of
        -- If there is no suitable network then we specify "auto" and hope that OpenStack will create one for us
        [] ->
            NoNetsAutoAllocate

        firstNet :: otherNets ->
            case otherNets of
                -- If there is only one network then we pick that one
                [] ->
                    OneNet firstNet

                -- If there are multiple networks then we let user choose and try to guess a good default
                _ ->
                    let
                        ( guessNet, goodGuess ) =
                            case maybeAutoAllocatedNet of
                                Just n ->
                                    ( n, True )

                                Nothing ->
                                    case maybeProjectNameNet of
                                        Just n ->
                                            ( n, True )

                                        Nothing ->
                                            ( firstNet, False )
                    in
                    MultipleNetsWithGuess projectNets guessNet goodGuess
