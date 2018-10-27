---
layout: post
title: Go-inject — Dependency Injection Library for Go
date: '2018-10-27 12:00:00 +0300'
categories: en posts
author: Max Strakhov
---
There are many resources on the web that try to define and explain [Dependency Injection](https://en.wikipedia.org/wiki/Dependency_injection) (a.k.a. DI). DI is a very useful software engineering technique, yet Go lacks any established libraries for it (although there were some attempts, which we will take a look at below). Not anymore! In this post we will introduce the [go-inject](https://github.com/monnoroch/go-inject) library and explore how it can improve code quality in standard Go application domain — web servers.

First, let us imagine we're a modern software startup whose product is an app that shows the weather. Our app's killer feature that will surely let us dominate weather prediction market is AI-based weather prediction. And of course, being a software startup, we need to build a cloud-native backend made of many microservices. Fortunately for us, our cloud provider is a company on the bleeding edge of AI research and it already had built a universal conversational AI and provided it to us as a [gRPC](https://grpc.io)-based API. If you don't know gRPC, don't worry, you can treat gRPC service definitions below as pseudocode that is used to auto-generate Go code with specified data structures and interfaces. This is how our system will look like:

<center>
	<img src="/images/posts/2018-10-22-go-inject-dependency-injection-library-for-go/architecture-1.svg"/>
</center>
<center>
Fig 1. Weather prediction service architecture.
</center>

Here is the gRPC service definition for the General AI service: it's a service for answering questions.

[`ai.proto` (code)](https://github.com/Monnoroch/go-inject/blob/88e8aca7c1b10aa3ac8dae23fefbc496cb3a63ef/examples/weather/proto/ai/ai.proto):

```proto
service Ai {
	rpc Ask(Question) returns (Answer) {}
}

message Question {
	string question = 1;
}

message Answer {
	string answer = 1;
}
```

The AI is simply a service that can give us free-form answers for free-form questions. Very powerful indeed. Now, there is a chance that the current version of the AI might just reply "42" to everything, but we're a startup and surely we can't build our own AI, right?

Let's take a closer look at our first microservice. It will use the above AI service to predict weather conditions for a specified space-time location:

[`weather.proto` (code)](https://github.com/Monnoroch/go-inject/blob/88e8aca7c1b10aa3ac8dae23fefbc496cb3a63ef/examples/weather/proto/weather.proto):

```proto
service WeatherPrediction {
	rpc Predict(SpaceTimeLocation) returns (Weather) {}
}

message SpaceTimeLocation {
	string location = 1;
	int64 timestamp = 2;
}

message Weather {
	string weather = 1;
}
```

Alright, the service API is defined, now it's time to implement it. We're going to be good engineers and separate user request handling logic and AI service interaction logic. Let's first implement the AI client. It's going to be a simple component that encapsulates the AI service API:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/88e8aca7c1b10aa3ac8dae23fefbc496cb3a63ef/examples/weather/ai/client.go):

```go
type AiClient struct {
	RawAiClient aiproto.AiClient
}

/// Ask AI service for weather at location and time specified in arguments.
func (self *AiClient) AskForWeather(
	ctx context.Context,
	location string,
	timestamp int64,
) string {
	answer, _ := self.RawAiClient.Ask(ctx, &aiproto.Question{
		Question: fmt.Sprintf(
			"What's the weather at location '%s' at time '%d'",
			location,
			timestamp,
		),
	})
	return answer.GetAnswer()
}
```

In this case we only have one method so we didn't need to have a struct. However, our sales team has already sold ten additional features to our customers that require using the AI service, so we know this component will grow and might as well just create a struct right away. Also note how we omit error handling: this is fine for a blog post, but terrible for production code. Don't do that.

Now that we have a way to obtain weather predictions, let's actually implement our weather prediction service. It's going to be a simple gRPC service, that uses our AI client, registered with a standard gRPC server:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/88e8aca7c1b10aa3ac8dae23fefbc496cb3a63ef/examples/weather/main.go):

```go
type Server struct {
	AiClient ai.AiClient
}

/// Handler for the WeatherPrediction.Predict RPC.
func (self *Server) Predict(
	ctx context.Context,
	request *proto.SpaceTimeLocation,
) (*proto.Weather, error) {
	weather := self.AiClient.AskForWeather(
		ctx,
		request.GetLocation(),
		request.GetTimestamp(),
	)
	return &proto.Weather{Weather: weather}, nil
}

func main() {
	aiConnection, _ := grpc.Dial("ai-service:80", grpc.WithInsecure())
	weatherPredictionServer := &Server{
		AiClient: ai.AiClient{
			RawAiClient: aiproto.NewAiClient(aiConnection),
		},
	}
	server := grpc.NewServer()
	proto.RegisterWeatherPredictionServer(
		server,
		weatherPredictionServer,
	)

	listener, _ := net.Listen("tcp", ":80")
	server.Serve(listener)
}
```

All done! Is there anything wrong with this code? Not really, but one thing one can notice right away is that request handling code is modular and follows the single responsibility principle, while the setup code in main is not as modular. In fact, it's just a bunch of spaghetti code wiring up the components. Imagine, what will happen to it when our RPC service has twenty RPC methods, ten external dependencies and fifty components developed by five engineers!

Ok, let's refactor the main function a little bit. Each component should have it's set up function that would later go to the component's package:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/002bf413f52e5544ff4eb03f0f31a6bd6f9a6142/examples/weather/main.go):

```go
func AiServiceEndpoint() string {
	return "ai-service:80"
}

func NewAiServiceGrpcConnection() *grpc.ClientConn {
	connection, _ := grpc.Dial(AiServiceEndpoint(), grpc.WithInsecure())
	return connection
}

func NewGrpcAiClient() aiproto.AiClient {
	return aiproto.NewAiClient(NewAiServiceGrpcConnection())
}

func NewAiClient() ai.AiClient {
	return ai.AiClient{RawAiClient: NewGrpcAiClient()}
}

func NewServer() *Server {
	return &Server{AiClient: NewAiClient()}
}

func main() {
	weatherPredictionServer := NewServer()

	...
}
```

Much more readable now! However, these constructor functions can't be put in their own packages close to the types they construct, because, for example, the AI client package is not supposed to know which URL does it need to connect to. Also this code is still not great, as there's no way to reuse it in different contexts. For example, we can not create an AI client to talk to a different endpoint to be used in a different gRPC server. Let's try to fix this issue by not hard coding dependencies but receiving them as arguments instead:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/a693800c9ccbf1ce3e45467329182e481a7c2768/examples/weather/main.go):

```go
func AiServiceEndpoint() string {
	return "ai-service:80"
}

func NewAiServiceGrpcConnection(aiServiceEndpoint string) *grpc.ClientConn {
	connection, _ := grpc.Dial(aiServiceEndpoint, grpc.WithInsecure())
	return connection
}

func NewGrpcAiClient(connection *grpc.ClientConn) aiproto.AiClient {
	return aiproto.NewAiClient(connection)
}

func NewAiClient(aiClient aiproto.AiClient) ai.AiClient {
	return ai.AiClient{RawAiClient: aiClient}
}

func NewServer(client ai.AiClient) *Server {
	return &Server{AiClient: client}
}

func main() {
	endpoint := AiServiceEndpoint()
	connection := NewAiServiceGrpcConnection(endpoint)
	aiClient := NewAiClient(NewGrpcAiClient(connection))
	weatherPredictionServer := NewServer(aiClient)

	...
}
```

Ok, now we have reusable constructor functions for all components, which we can actually put in different packages, but we're back to spaghetti code in main. Is there no way to write maintainable setup code?! Well, we can continue refactoring main and split it into a few helper functions with good readable names. However, there's a fundamental problem here: either you have configurable constructors that accept dependencies as arguments and then you write spaghetti code to wire them together, or you hard code these dependencies and not reuse your constructor functions. There's no way around that, no matter how much you refactor your code.

Or is there? Let's imagine a system that allows us to write independent, reusable chunks of code for creating components, just as we did in the last example, and then automatically generates all the spaghetti code that we have in main. Can this be done? Indeed it can! This is what `go-inject` and any other Dependency Injection library does. Two most popular examples and the ones I'm most familiar with are [Guice](https://github.com/google/guice) and [Dagger](https://google.github.io/dagger). Both are Java frameworks, which implies a heavy weight approach with infinite configurability and thousands of features. Can a similar tool be designed for Go with Go's strengths and philosophy in mind? Well, there's no harm in trying, so let's do just that.

## Dependency Injection Library for Go

But let's discuss this idea for a bit first. People who moved from Java to Go will immediately be alert at this point. They, just like me, probably moved for Go's simplicity, the culture to be explicit and tools that are stupid (in a good way) rather than clever and complicated, which is what we see in Java a lot. If I were to build a Dependency Injection library, it would have to be aligned with Go's core values.

#### It has to do one thing only

Namely, generate boilerplate for wiring up dependencies. Libraries that do many loosely related things are unwelcome in Go. This doesn't mean a library has to be small in size though, for example, `net/http` package is quite big, but it still does only one job — implements a generic HTTP server.

#### The API needs to be expressive

All common patterns have to be supported along with as many reasonable uncommon ones as possible. `net/http` is also a great example here: I have never found any missing features or lacking flexibility there for day-to-day software (although you might want to use `fasthttp` if your infrastructure doesn't scale horizontally or the deployment is huge and bound by the HTTP server).

#### The API also needs to be concise

There should be user-friendly helpers for common patterns. Just as `encoding/json` package allows adding `json:` annotations instead of implementing the complicated `RawMessage` interface, our DI library needs to provide syntactic-sugar-like helpers for common operations.

#### The library needs to be transparent

The implementation needs to be simple and hackable. This is the bit that is often missed by software engineers. There is a culture that if your interface is good, the implementation doesn't matter all that much. However, the truth is that all abstractions leak. Your new abstraction will also leak. People *will* have to look at the implementation from time to time, either to understand it, or to fix a problem, or maybe even to bypass your abstraction in a context you just didn't anticipate. One of the best parts of switching to Go for me was that I can easily read and understand the source code of most good libraries. This is much less true in many other software engineering cultures.

#### Backward compatibility

Existing code should not require modification to use a DI library. New code can be made DI-library aware to get convenience features, but should not be required to do so. Backwards compatibility is a must for seamless integration with both existing code and third party libraries.

#### It has to feel like a Go library

In addition to all the above formal criteria, a DI library for Go just has to feel native. For example, it has to leverage type system as much as possible, make it easy to build tools on top of it and be Go-ish in general. This is not easy to formalize, but very easy to feel.

## Enter go-inject

A piece of code is worth a thousand words, so let's just reimplement our main function above with `go-inject` and then discuss the implementation. Here's a first simplistic pseudo-implementation:

[`grpc/module.go` (code)](https://github.com/Monnoroch/go-inject/blob/316fe41bb3d0c7e82edd731d6215aec78a302efd/examples/weather/grpc/module.go):

```go
/// A module for providing gRPC client components.
type GrpcClientModule struct{}

func (_ GrpcClientModule) ProvideConnection(
	endpoint string,
) (*grpc.ClientConn, error) {
	connection, err := grpc.Dial(endpoint, grpc.WithInsecure())
	return connection, err
}
```

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/316fe41bb3d0c7e82edd731d6215aec78a302efd/examples/weather/ai/client.go):

```go
/// A module for providing AI service client components.
type AiServiceClientModule struct{}

func (_ AiServiceClientModule) ProvideGrpcClient(
	connection *grpc.ClientConn,
) aiproto.AiClient {
	return aiproto.NewAiClient(connection)
}

func (_ AiServiceClientModule) ProvideAiClient(
	client aiproto.AiClient,
) AiClient {
	return AiClient{RawAiClient: client}
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/316fe41bb3d0c7e82edd731d6215aec78a302efd/examples/weather/main.go):

```go
import "github.com/monnoroch/go-inject"

/// A module for providing a configured weather prediction server.
type WeatherPredictionServerModule struct{}

/// Provider returning the AI service endpoint, to be used by the gRPC client module.
func (_ WeatherPredictionServerModule) ProvideGrpcEndpoint() string {
	return "ai-service:80"
}

func (_ WeatherPredictionServerModule) ProvideServer(
	client ai.AiClient,
) *Server {
	return &Server{AiClient: client}
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcClientModule{},
		ai.AiServiceClientModule{},
		WeatherPredictionServerModule{},
	)
	weatherPredictionServer := injector.MustGet(new(*Server)).(*Server)

	...
}
```

Doesn't look that simple, eh? Well, let's take a closer look before judging. Ok, so we grouped our glue code into three structs called modules: gRPC client module, AI service client module and the weather prediction server module. Each module can be put in the corresponding package and unit-tested separately. For example, we placed the AI service client module to the `ai` package and even made the gRPC client module into a general-purpose library. Each module has providers — methods named `ProvideSomething`. These methods each return one of the components used in our application and receive it's dependencies as arguments. Notice how these providers map directly to constructor functions from the second main refactoring example above. In these providers we do not hardcode the dependencies, so they are reusable in multiple contexts.

Okay, we converted our constructors into struct methods, so not much changed just yet. We even had to write a bit more boilerplate to have methods instead of functions. So how is this better? Enter `Injector`. Injector is a core component of the library. An injector is configured with a collection of modules and can provide all the components by calling providers and automatically wiring up all their dependencies. Basically, the `injector.MustGet(new(*Server)).(*Server)` call generates all the boilerplate we had to write before for creating a server instance using configurable constructor functions. Another interesting point to note is that we are not ignoring errors that `grpc.Dial` can return, but our code is still clear of error-handling code. That is because `go-inject` handles all errors returned from providers for you and bubbles them up to the caller. A nice thing to get for free, isn't it?

In short, we put our constructor functions into modules as providers, configure the injector with a collection of modules and then use it to dynamically generate component creation code.

Now, you might have spotted a problem with this code: what if we have two providers returning a `string`? Which one will the system pick? Well, there's no way for it to decide, so we have to do something about it. Similar to [Guice](https://github.com/google/guice/wiki/BindingAnnotations), `go-inject` requires the user to mark annotate all values, so that if there are two `string` providers, these strings are annotated differently and when you depend on a `string` you also specify which string this is. Unlike Java, Go doesn't have any built-in syntax for annotating declarations, so we have to improvise. The option I chose for `go-inject` is to always declare dependencies in pairs: a value type and an annotation type. It's much easier to explain with code, so here's the version of the above code with annotations:

[`grpc/module.go` (code)](https://github.com/Monnoroch/go-inject/blob/96ebd38a01cb954d5cdc8f4047bbbc0ed7c19071/examples/weather/grpc/module.go):

```go
/// Annotation used by the gRPC client module.
type GrpcClient struct{}

/// A module for providing gRPC client components.
type GrpcClientModule struct{}

func (_ GrpcClientModule) ProvideConnection(
	endpoint string, _ GrpcClient,
) (*grpc.ClientConn, GrpcClient, error) {
	connection, err := grpc.Dial(endpoint, grpc.WithInsecure())
	return connection, GrpcClient{}, err
}
```

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/96ebd38a01cb954d5cdc8f4047bbbc0ed7c19071/examples/weather/ai/client.go):

```go
/// Annotation used by the AI service client module.
type AiService struct{}

/// A module for providing AI service client components.
type AiServiceClientModule struct{}

func (_ AiServiceClientModule) ProvideGrpcClient(
	connection *grpc.ClientConn, _ grpcinject.GrpcClient,
) (aiproto.AiClient, AiService) {
	return aiproto.NewAiClient(connection), AiService{}
}

func (_ AiServiceClientModule) ProvideAiClient(
	client aiproto.AiClient, _ AiService,
) (AiClient, AiService) {
	return AiClient{RawAiClient: client}, AiService{}
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/96ebd38a01cb954d5cdc8f4047bbbc0ed7c19071/examples/weather/main.go):

```go
/// Annotation used by the weather prediction server module.
type WeatherPrediction struct{}

/// A module for providing a configured weather prediction server.
type WeatherPredictionServerModule struct{}

/// Provider returning the AI service endpoint, to be used by the gRPC client module.
func (_ WeatherPredictionServerModule) ProvideGrpcEndpoint() (string, grpcinject.GrpcClient) {
	return "ai-service:80", grpcinject.GrpcClient{}
}

func (_ WeatherPredictionServerModule) ProvideServer(
	client ai.AiClient, _ ai.AiService,
) (*Server, WeatherPrediction) {
	return &Server{AiClient: client}, WeatherPrediction{}
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcClientModule{},
		ai.AiServiceClientModule{},
		WeatherPredictionServerModule{},
	)
	weatherPredictionServer := injector.MustGet(
		new(*Server), WeatherPrediction{},
	).(*Server)

	server := grpc.NewServer()
	proto.RegisterWeatherPredictionServer(
		server,
		weatherPredictionServer,
	)
	listener, _ := net.Listen("tcp", ":80")
	server.Serve(listener)
}
```

Notice how all provided values and dependencies are now "annotated" using a second value with the annotation type, and how we request the `*Server` type with the `WeatherPrediction` annotation from the injector. By the way, since now we can have multiple providers of the same type, we can go even further and have a gRPC server provider:

[`grpc/module.go` (code)](https://github.com/Monnoroch/go-inject/blob/cbff69f2c7705c343d13b050cb613aaf5f941697/examples/weather/grpc/module.go):

```go
...

/// Annotation used by the gRPC server module.
type GrpcServer struct{}

/// A module for providing gRPC server components.
type GrpcServerModule struct{}

func (_ GrpcServerModule) ProvideServer() (*grpc.Server, GrpcServer) {
	return grpc.NewServer(), GrpcServer{}
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/cbff69f2c7705c343d13b050cb613aaf5f941697/examples/weather/main.go):

```go
...

func (_ WeatherPredictionServerModule) ProvideGrpcServer(
	grpcServer *grpc.Server, _ grpcinject.GrpcServer,
	weatherPredictionServer *Server, _ WeatherPrediction,
) (*grpc.Server, WeatherPrediction) {
	proto.RegisterWeatherPredictionServer(
		grpcServer,
		weatherPredictionServer,
	)
	return grpcServer, WeatherPrediction{}
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcServerModule{},
		grpcinject.GrpcClientModule{},
		ai.AiServiceClientModule{},
		WeatherPredictionServerModule{},
	)
	server := injector.MustGet(
		new(*grpc.Server), WeatherPrediction{},
	).(*grpc.Server)
	listener, _ := net.Listen("tcp", ":80")
	server.Serve(listener)
}
```

Notice how we're not actually creating a gRPC server in the weather prediction module, but rather receive it as a dependency, configure it and return it back to the user with a different annotation. Pretty neat. This example might not look particularly impressive, but once you have tens of different components, command line flags, environment variables and configuration routines that can be reused in different contexts, restructuring code into providers and modules starts to provide value (no pun intended).

This is basically it. The library only has three core concepts: modules with providers for providing components, annotations to disambiguate values of identical types and the injector to wire these providers together. Now that we understand the core, let's dive in some more subtle features.

### Singletons

Components often should be singletons: only have one instance for the whole program. In fact, in our example we already have this case: there should be only one gRPC connection to the AI service. Sure, we only inject it once, so it's fine now, but we might want to inject it in multiple components in the future. The code will still be correct, but will call the gRPC connection provider twice, which means it will create two gRPC connections, which might hurt performance and is certainly not what we want to do. We want the AI service connection to be a singleton. `go-inject` has a tool for that: cached providers. We can't actually make the gRPC connection a singleton because we might also want to connect to other services, so let's make the AI client a singleton. This can be done by prefixing the provider name with `ProvideCached` which will make this provider into a cached provider:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/e11885c373159ffdaf68fd705b81f69b69237f88/examples/weather/ai/client.go):

```go
...

func (_ AiServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ grpcinject.GrpcClient,
) (aiproto.AiClient, AiService) {
	return aiproto.NewAiClient(connection), AiService{}
}
...
```

Now the gRPC client for the AI service is cached and all components that depend on `AiClient` will get the same instance of `aiproto.AiClient`, so only one gRPC connection will be established. Note how this behaviour is not default. I have seen many production bugs because some things got cached when they shouldn't have been, so I decided that explicit is better than implicit and disabled caching by default.

### Private providers

In the example above `AiServiceClientModule` provides our `AiClient` component and gRPC-generated `aiproto.AiClient` annotated with `AiService`. This is not actually what we wanted. We want to provide our `AiClient` component and make the generated dependency component an implementation detail that is not exposed to users of our module. I've spent some time designing how this could be implemented; the options included special annotation modifiers and `ProvidePrivate` prefix. All these options didn't quite fit. They were all clumsy and hard to explain. So I scrapped everything and started from the basic principle of making the API feel native to Go developers. Surprisingly, I found that I don't have to do anything at all! One can just define a separate annotation for providers that should be private and make that annotation a private struct. That way we get module-scoped privacy rules native to Go and we get it for free: it's a zero-implementation and zero-documentation feature! Let's demonstrate it for our example:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/12df1c9bb04382afbb0ffad0b5394b654f07846b/examples/weather/ai/client.go):

```go
/// Annotation used by the AI service client module.
type AiService struct{}

/// Annotation for private providers.
type private struct{}

/// A module for providing AI service client components.
type AiServiceClientModule struct{}

func (_ AiServiceClientModule) ProvideGrpcClient(
	connection *grpc.ClientConn, _ GrpcClient,
) (aiproto.AiClient, private) {
	return aiproto.NewAiClient(connection), private{}
}

func (_ AiServiceClientModule) ProvideAiClient(
	client aiproto.AiClient, _ private,
) (AiClient, AiService) {
	return AiClient{ RawAiClient: aiClient }, AiService{}
}
```

### Reducing boilerplate

All code above is great but it is a little bit verbose. Especially it's too verbose for structs that are created by just putting dependencies in fields. This does not align with the goal of being concise. To make the code more concise I added a special tool for this case: automatic field injection. `go-inject` library comes with `autoinject` package with the `autoinject.AutoInjectModule` API for generating providers like these. `autoinject.AutoInjectModule` receives a type and returns a module that can provide that type by copying dependencies into it's fields. The catch here is that only public fields can be automatically injected. Auto-inject modules can also be configured with output and field annotations. For example:

```go
import "github.com/monnoroch/go-inject/auto"

autoinject.AutoInjectModule(new(AiClient)).
	WithAnnotation(AiService{})
	WithFieldAnnotations(struct{
		RawAiClient private
	}{}),
```

generates a module with a provider that returns `AiClient` annotated with `AiService` and with `RawAiClient` field populated by a value of it's type in the `AiClient` struct, annotated with `private`. This is exactly what we had before in the `ProvideAiClient` provider, but now it's generated for us!

Let's transform our code to use auto-inject modules:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/3a3fd9034689933d975552776858515db1286bc3/examples/weather/ai/client.go):

```go
/// A module for providing AI service client components.
type aiServiceClientModule struct{}

func (_ aiServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ grpcinject.GrpcClient,
) (aiproto.AiClient, private) {
	return aiproto.NewAiClient(connection), private{}
}

func AiServiceClientModule() inject.Module {
	return inject.CombineModules(
		aiServiceClientModule{},
		autoinject.AutoInjectModule(new(AiClient)).
			WithAnnotation(AiService{}).
			WithFieldAnnotations(struct {
				RawAiClient private
			}{}),
	)
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/3a3fd9034689933d975552776858515db1286bc3/examples/weather/main.go):

```go
...

/// A module for providing a configured weather prediction server.
type weatherPredictionServerModule struct{}

/// Provider returning the AI service endpoint, to be used by the gRPC client module.
func (_ weatherPredictionServerModule) ProvideGrpcEndpoint() (string, grpcinject.GrpcClient) {
	return "ai-service:80", grpcinject.GrpcClient{}
}

func (_ weatherPredictionServerModule) ProvideGrpcServer(
	grpcServer *grpc.Server, _ grpcinject.GrpcServer,
	weatherPredictionServer *Server, _ WeatherPrediction,
) (*grpc.Server, WeatherPrediction) {
	proto.RegisterWeatherPredictionServer(
		grpcServer,
		weatherPredictionServer,
	)
	return grpcServer, WeatherPrediction{}
}

func WeatherPredictionServerModule() inject.Module {
	return inject.CombineModules(
		weatherPredictionServerModule{},
		autoinject.AutoInjectModule(new(*Server)).
			WithAnnotation(WeatherPrediction{}).
			WithFieldAnnotations(struct {
				AiClient ai.AiService
			}{}),
	)
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcClientModule{},
		grpcinject.GrpcServerModule{},
		ai.AiServiceClientModule(),
		WeatherPredictionServerModule(),
	)

	...
}
```

Okay, that's a lot of changes, let's go through them one-by-one. First of all, notice how we replaced creating module structs with function calls in the injector configuration and made our modules private, so that they can only be created by these helper functions. We did that because our AI client and weather prediction server modules are now not just structs, but are themselves lists of two modules each: the module we had before and an auto-inject module for providing the structs. Wrapping a collection of modules into a single module can be done with `inject.CombineModules` function. Only providers that do actual interesting work are left to be coded manually now. In this case we are reasonably sure that there will only be one component of type `AiClient` in our application, so we can simplify code even more by omitting it's annotations:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/0742f07184f92305a6273afa1893a850e1fd3ebc/examples/weather/ai/client.go):

```go
func AiServiceClientModule() inject.Module {
	return inject.CombineModules(
		aiServiceClientModule{},
		autoinject.AutoInjectModule(new(AiClient)).
			WithFieldAnnotations(struct {
				RawAiClient private
			}{}),
	)
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/0742f07184f92305a6273afa1893a850e1fd3ebc/examples/weather/main.go):

```go
func (_ weatherPredictionServerModule) ProvideGrpcServer(
	grpcServer *grpc.Server, _ grpcinject.GrpcServer,
	weatherPredictionServer *Server, _ autoinject.Auto,
) (*grpc.Server, WeatherPrediction) {
	proto.RegisterWeatherPredictionServer(
		grpcServer,
		weatherPredictionServer,
	)
	return grpcServer, WeatherPrediction{}
}

func WeatherPredictionServerModule() inject.Module {
	return inject.CombineModules(
		weatherPredictionServerModule{},
		autoinject.AutoInjectModule(new(*Server)),
	)
}
```

Now auto-injected structs will be provided annotated with `autoinject.Auto`. In fact, we can simplify the code even further. Often when developing application components that are not meant to be used as a general purpose library, the author can provide default code for creating the component. With `go-inject` this can be done by implementing the `autoinject.AutoInjectable` interface. Let's do that for our AI client:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/3c3c205f097311b3e6d804b0704754dbfb791887/examples/weather/ai/client.go):

```go
func (self AiClient) ProvideAutoInjectAnnotations() interface{} {
	return struct{
		RawAiClient private
	}{}
}
```

Now if we want to create `AiClient` configured with default dependencies, we don't need to specify the annotations any more:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/3c3c205f097311b3e6d804b0704754dbfb791887/examples/weather/ai/client.go):

```go
func AiServiceClientModule() inject.Module {
	return inject.CombineModules(
		aiServiceClientModule{},
		autoinject.AutoInjectModule(new(AiClient)),
	)
}
```

With this design the author of the component can define default annotations for field dependencies, but the user can still override individual dependencies when creating an auto-inject module.

*Implementing this interface is similar to creating an `@Inject` constructor for a class in Guice.*

Again, all this does not seem like much, but once you have a lot of dependencies, it really adds up and auto-inject modules can reduce the code base significantly.

### Code reuse

Ok, we've got cloud, microservices and AI. What's missing? Blockchain, of course! As our startup turns into an evil money-sucking corporation, we will want to make our users pay for weather predictions. Fortunately, we use gRPC, so we can make a backwards-compatible change to the API that will allow us to bill users:

[`weather.proto` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/proto/weather.proto):

```proto
message SpaceTimeLocation {
	string location = 1;
	int64 timestamp = 2;
	int64 user_id = 3; // we don't have funding to refactor it into an enclosing message for readability
}
```

Nice, now we can bill the user and reject requests without a user id. IPO, here we come! But first we need to implement this new feature. Fortunately, our cloud provider is a great one and it already provides a shared blockchain service our users can register in and authorize us to make payments with. Here is its API:

[`blockchain.proto` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/proto/blockchain/blockchain.proto):

```proto
service Blockchain {
	rpc Pay(PayRequest) returns (PayResponse) {}
}

message PayRequest {
	int64 from = 1;
	int64 to = 2;
	int64 amount_micro_eth = 3;
}

message PayResponse {}
```
Here is how our new architecture will look like:

<center>
	<img src="/images/posts/2018-10-22-go-inject-dependency-injection-library-for-go/architecture-2.svg"/>
</center>
<center>
Fig 2. Weather prediction service with billing architecture.
</center>


Now let's use this service to implement billing customers:

[`blockchain/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/blockchain/client.go):

```go
type BlockchainClient struct {
	RawBlockchainClient blockchainproto.BlockchainClient
}

/// Make payment using the blockchain service.
func (self *BlockchainClient) Pay(
	ctx context.Context,
	userId int64,
) bool {
	_, err := self.RawBlockchainClient.Pay(ctx, &blockchainproto.PayRequest{
		From:           userId,
		To:             12345, // our app's user id; not enough funding to make it a flag
		AmountMicroEth: 5,
	})
	return err == nil
}
```

And create a module fom providing it, similar to the `AiClient` module:

[`blockchain/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/blockchain/client.go):

```go
func (self BlockchainClient) ProvideAutoInjectAnnotations() interface{} {
	return struct {
		RawBlockchainClient private
	}{}
}

/// Annotation used by the AI service client module.
type BlockchainService struct{}

/// Annotation for private providers.
type private struct{}

/// A module for providing AI service client components.
type blockchainServiceClientModule struct{}

func (_ blockchainServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ grpcinject.GrpcClient,
) (blockchainproto.BlockchainClient, private) {
	return blockchainproto.NewBlockchainClient(connection), private{}
}

func BlockchainServiceClientModule() inject.Module {
	return inject.CombineModules(
		blockchainServiceClientModule{},
		autoinject.AutoInjectModule(new(BlockchainClient)),
	)
}
```

Now we modify our weather prediction server to use the new component:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/main.go):

```go
type Server struct {
	AiClient         ai.AiClient
	BlockchainClient blockchain.BlockchainClient
}

/// Handler for the WeatherPrediction.Predict RPC.
func (self *Server) Predict(
	ctx context.Context,
	request *proto.SpaceTimeLocation,
) (*proto.Weather, error) {
	if !self.BlockchainClient.Pay(ctx, request.GetUserId()) {
		return &proto.Weather{}, errors.New("no money -- no weather!")
	}
	weather := self.AiClient.AskForWeather(
		ctx,
		request.GetLocation(),
		request.GetTimestamp(),
	)
	return &proto.Weather{Weather: weather}, nil
}
```

And finally we update the weather prediction server module to inject and configure the new component:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/76bb82094376c7d87f6b43accee131e930eb0752/examples/weather/main.go):

```go
/// Provider returning the AI service endpoint, to be used by the gRPC client module.
func (_ weatherPredictionServerModule) ProvideGrpcEndpoint() (string, grpcinject.GrpcClient) {
	return "ai-service:80", grpcinject.GrpcClient{}
}

/// Provider returning the blockchain service endpoint, to be used by the gRPC client module.
func (_ weatherPredictionServerModule) ProvideBlockchainGrpcEndpoint() (string, grpcinject.GrpcClient) {
	return "blockchain-service:80", grpcinject.GrpcClient{}
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcServerModule{},
		grpcinject.GrpcClientModule{},
		ai.AiServiceClientModule(),
		blockchain.BlockchainServiceClientModule(),
		WeatherPredictionServerModule(),
	)

	...
}
```

Note how we don't need to modify `WeatherPredictionServerModule` because of automatic injection and only need to provide a new endpoint to configure a new gRPC connection to the blockchain service. But wait... now we provide two `string`-s annotated with `GrpcClient`. That's not good. It meand that to have a second gRPC client we now need a second gRPC client module with a separate annotation, so there goes our general purpose library idea. Or does it? To make creating general purpose libraries possible `go-inject` has a feature called annotation rewriting. Basically, what we want to achieve here is to be able to write a gRPC client module once and then be able to instantiate it with different annotations for different clients. This is exactly what annotation rewriting lets us do. Let's reimplement the gRPC client module with it:

[`grpc/module.go` (code)](https://github.com/Monnoroch/go-inject/blob/1367d662a3ae945b2de9fbf3f795c411605f5035/examples/weather/grpc/module.go):

```go
import "github.com/monnoroch/go-inject/rewrite"

/// Annotation used by the gRPC client module.
type grpcClient struct {}

/// A module for providing gRPC client components.
type grpcClientModule struct {}

func (_ grpcClientModule) ProvideConnection(
	endpoint string, _ grpcClient,
) (*grpc.ClientConn, grpcClient, error) {
	connection, err := grpc.Dial(endpoint)
	return connection, grpcClient{}, err
}

func GrpcClientModule(annotation inject.Annotation) inject.Module {
	return rewrite.RewriteAnnotations(
		grpcClientModule{},
		rewrite.AnnotationsMapping{
			grpcClient{}: annotation,
		},
	)
}
```

You can immediately spot the trick with making the module private and providing a helper function to create it now, but what does the new do? `rewrite.RewriteAnnotations` is a module wrapper function that receives a module and returns it's copy where all annotations that are keys in the annotations mapping get replaced with corresponding values. In this case `GrpcClientModule(ai.AiService{})` will return a copy of `grpcClientModule` with a provider that receives a `string` annotated with `ai.AiService` and returns a `*grpc.ClientConn` annotated with `ai.AiService`. Let's change our code function to use it:

[`ai/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/1367d662a3ae945b2de9fbf3f795c411605f5035/examples/weather/ai/client.go):

```go
...

func (_ aiServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ AiService,
) (aiproto.AiClient, private) {
	return aiproto.NewAiClient(connection), private{}
}
```

[`blockchain/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/1367d662a3ae945b2de9fbf3f795c411605f5035/examples/weather/blockchain/client.go):

```go
...

func (_ blockchainServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ BlockchainService,
) (blockchainproto.BlockchainClient, private) {
	return blockchainproto.NewBlockchainClient(connection), private{}
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/1367d662a3ae945b2de9fbf3f795c411605f5035/examples/weather/main.go):

```go
...

/// Provider returning the AI service endpoint, to be used by the gRPC client module.
func (_ weatherPredictionServerModule) ProvideGrpcEndpoint() (string, ai.AiService) {
	return "ai-service:80", ai.AiService{}
}

/// Provider returning the blockchain service endpoint, to be used by the gRPC client module.
func (_ weatherPredictionServerModule) ProvideBlockchainGrpcEndpoint() (string, blockchain.BlockchainService) {
	return "blockchain-service:80", blockchain.BlockchainService{}
}

func main() {
	injector, _ := inject.InjectorOf(
		grpcinject.GrpcServerModule{},
		grpcinject.GrpcClientModule(ai.AiService{}),
		grpcinject.GrpcClientModule(blockchain.BlockchainService{}),
		ai.AiServiceClientModule(),
		blockchain.BlockchainServiceClientModule(),
		WeatherPredictionServerModule(),
	)

	...
}
```

Now both gRPC connections will be configured with correct endpoints and we have a reusable general purpose library for creating gRPC connections.

### Lazy dependencies

Let's look at a different problem. We want to have a development instance of our service for the team members to test new features, which will not require it's users to actually pay anything to us. Since `blockchainproto.BlockchainClient` is an interface, we can have a second non-gRPC implementation that always authorizes payments:

[`blockchain/fake_client.go` (code)](https://github.com/Monnoroch/go-inject/blob/39db1150e48abdcfb34ac2fa211e8aca3cbf422a/examples/weather/blockchain/fake_client.go):

```go
type develBlockchainClient struct{}

/// Make all payments succeed.
func (self develBlockchainClient) Pay(
	_ context.Context,
	_ *blockchainproto.PayRequest,
	_ ...grpc.CallOption,
) (*blockchainproto.PayResponse, error) {
	return &blockchainproto.PayResponse{}, nil
}
```

Okay, we have the logic, let's configure our `BlockchainClient` to use `develBlockchainClient` instead of the generated `blockchainproto.BlockchainClient`. We will configure it with a boolean flag provided by the weather prediction server module and select the `blockchainproto.BlockchainClient` implementation conditionally:

[`blockchain/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/39db1150e48abdcfb34ac2fa211e8aca3cbf422a/examples/weather/blockchain/client.go):

```go
func (_ blockchainServiceClientModule) ProvideCachedGrpcClient(
	connection *grpc.ClientConn, _ BlockchainService,
	develClient develBlockchainClient, _ private,
	develInstance bool, _ BlockchainService,
) (blockchainproto.BlockchainClient, private) {
	if develInstance {
		return develClient, private{}
	} else {
		return blockchainproto.NewBlockchainClient(connection), private{}
	}
}

func BlockchainServiceClientModule() inject.Module {
	return inject.CombineModules(
		blockchainServiceClientModule{},
		autoinject.AutoInjectModule(new(BlockchainClient)),
		autoinject.AutoInjectModule(new(develBlockchainClient)).
			WithAnnotation(private{}),
	)
}
```

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/39db1150e48abdcfb34ac2fa211e8aca3cbf422a/examples/weather/main.go):

```go
func (_ weatherPredictionServerModule) ProvideIsDevelInstance() (bool, blockchain.BlockchainService) {
	return true, blockchain.BlockchainService{} // TODO: make it into a flag
}
```

The code looks correct, but there is a problem there. Even if `develInstance` is true, the gRPC version of `blockchainproto.BlockchainClient` is still injected, which means the gRPC connection is still established, even though we don't use it. And it's not just a performance issue, this also means that we can't run the devel instance locally or in environments where there's no blockchain service endpoint provided. We need to be able to inject dependencies conditionally. In this case, only if `develInstance` is false. `go-inject` provides this facility with the lazy dependencies feature. To inject a dependency lazily, just inject a function that returns it instead. Here's the code:

[`blockchain/client.go` (code)](https://github.com/Monnoroch/go-inject/blob/2cab46cf96e92679a455c3cc4855a56a31115db2/examples/weather/blockchain/client.go):

```go
func (_ blockchainServiceClientModule) ProvideCachedGrpcClient(
	connection func() *grpc.ClientConn, _ BlockchainService,
	develClient develBlockchainClient, _ private,
	develInstance bool, _ BlockchainService,
) (blockchainproto.BlockchainClient, private) {
	if develInstance {
		return develClient, private{}
	} else {
		return blockchainproto.NewBlockchainClient(connection()), private{}
	}
}
```

Yep, it's that simple. Now we only create the client (and thus establish the gRPC connection) when we're not in the devel instance. It just works. As of now, lazy value functions can only be called in the provider that injects them and will panic if you try to store them and call later. This behaviour might be changed in the future though. There is a catch, however: this feature means that injecting functions is not supported, they are always treated as lazy dependencies. It's not a major issue though, because you can still inject alias types of functions:

```go
type Predicate func(int) bool

type Absolute struct{}

func (_ Predicate) ProvideAbs(
	value int, _ inject.Annotation,
	isPositive Predicate, _ inject.Annotation,
) (int, Absolute) {
	if isPositive(value) {
		return value, Absolute{}
	} else {
		return -value, Absolute{}
	}
}
```

This will inject an actual function, not a lazy `int` value.

### Hacking API

Still not enough features? One of your common patterns doesn't have a convenient tool? Perhaps, you are feeling like a hacker today? Remember the goal of this library being expressive? It is! In fact, the library has a feature specifically for you: dynamic modules. Dynamic module is a very simple concept: instead of writing providers as methods on regular static modules, implement the `inject.DynamicModule` interface with just one method and create providers at runtime with anonymous functions or reflection. Let's take a look at a simple example for generating providers for constants:

[`constant/module.go` (code)](https://github.com/Monnoroch/go-inject/blob/8fa599cb0ed4f19848fff8bcb7006344f76b1329/examples/weather/constant/module.go):

```go
type constantModule struct {
	value      interface{}
	annotation inject.Annotation
}

func (self constantModule) Providers() ([]inject.Provider, error) {
	annotationType := reflect.TypeOf(self.annotation)
	return []inject.Provider{inject.NewProvider(reflect.MakeFunc(
		reflect.FuncOf(
			[]reflect.Type{},
			[]reflect.Type{
				reflect.TypeOf(self.value),
				annotationType,
			},
			false,
		),
		func(_ []reflect.Value) []reflect.Value {
			return []reflect.Value{
				reflect.ValueOf(self.value),
				reflect.Zero(annotationType),
			}
		},
	),
	)}, nil
}

/// Creates a module that provides a constant value with a specified annotation.
func ConstantModule(value interface{}, annotation inject.Annotation) inject.Module {
	return constantModule{value: value, annotation: annotation}
}
```

It's a very simple dynamic module that generates a single provider with reflection. That provider doesn't have any dependencies and just provides a constant value with a specified annotation. Let's use it to provide our endpoints and the devel flag instead of writing providers manually:

[`main.go` (code)](https://github.com/Monnoroch/go-inject/blob/8fa599cb0ed4f19848fff8bcb7006344f76b1329/examples/weather/main.go):

```go
func WeatherPredictionServerModule() inject.Module {
	return inject.CombineModules(
		weatherPredictionServerModule{},
		constant.ConstantModule("ai-service:80", ai.AiService{}),
		constant.ConstantModule("blockchain-service:80", blockchain.BlockchainService{}),
		constant.ConstantModule(true, blockchain.BlockchainService{}),
		autoinject.AutoInjectModule(new(*Server)),
	)
}
```

In fact, both automatic injection module and annotation rewrite wrapper and even regular static modules are implemented using this API, so it's very powerful and basically provides a way to implement any feature you've seen in other DI frameworks (not that you necessarily should though).

*If you feel that your provider generator would be useful to most users of `go-inject`, feel free to submit a design document with a proposal and a reference implementation to add it to the core repository.*

### Implementation

If you're still reading this post, then you probably interested enough to remember the goal of implementation being transparent. Simple implementation is very important for any piece of software and even more so for libraries to be used by other developers. If you followed the post, you might already have a feeling how the library is implemented (which is a good indicator that it is, in fact, transparent!). There are two stages: configuring an injector and providing values.

#### Configuring an injector

The first stage is the `inject.InjectorOf` call. It receives a list of modules, and collects dynamic providers from all of them into one big map, keyed by (value type, annotation type) pairs. For static modules it first wraps them with a struct implementing the `inject.DynamicModule` interface to extract providers from struct methods with reflection. This stage also does all provider validation, making sure that providers are named properly and that there's the right number of inputs and outputs.

#### Providing values

The second stage is providing values using `injector.Get` and `injector.MustGet` methods. These are also pretty straightforward: they receive a value type, an annotation type, search the providers map for a corresponding provider, recursively provide it's dependencies and inject them into that provider. For lazy dependencies, they inject a function calling `injector.Get` instead. There's a bit of complexity around cached providers, but it's not critical for understanding the implementation.

The whole description fits a couple of paragraphs and it doesn't even omit much detail. The whole library is under 3kloc with tests, so the implementation is very compact as well.

### Alternatives

Now that we've seen what we can do with `go-inject`, let's look at the alternatives. To my best knowledge, there are five of them (as of Q3 2018):

- [gongular](https://github.com/mustafaakin/gongular)
- [facebookgo/inject](https://github.com/facebookgo/inject)
- [alice](https://github.com/magic003/alice)
- [impinj/go-inject](https://github.com/impinj/go-inject)
- [alecthomas/inject](https://github.com/alecthomas/inject)

#### Gongular

[Gongular](https://github.com/mustafaakin/gongular) is a web framework that includes DI. I found this problematic:

- being a framework, it violates the "do one thing" principle
- if you already use another web framework, you can't use it for DI
- it provides DI for data as well as component dependencies. My experience shows that it is bug-prone and not easily debuggable

Because of these reasons I rejected this package immediately when researching the problem.

#### `impinj/go-inject`, `facebookgo/inject` and `alice`

These three packages are quite similar. They all use struct tags instead of `go-inject`-style annotations. The obvious problem with this interface is that you can't provide non-struct values, which is critical for providing configuration flags, endpoints and the like. The less obvious problem is that the interface is based on annotation strings and is thus untyped, which means that the compiler will not be able to verify your code. This also means "private" providers are impossible, which breaks encapsulation. In addition to that, `impinj/go-inject` and `facebookgo/inject` also have another problem: they require you to actually annotate the struct itself, rather than a separate entity (a module) and thus these libraries will not work with the existing code. `alice` does not have this flaw as annotations are moved to separate structs, called modules.

#### `alecthomas/inject`

This project is the most similar one to `go-inject`. It also provides the struct-based modules interface, but it doesn't provide a way to provide multiple values of the same type (which is supported by all other libraries, including `go-inject`). It also provides ways to generate providers in runtime, but they are tailored to particular use-cases, such as binding a constant, rather than providing a generic interface for extending the library.

### Conclusion

This library is used in production Go backend software for more than a year and engineers who use it enjoy it a lot as it helps them to manage complexity. The effort to open source it is new, and it was significantly redesigned for simplicity in the process. It is definitely not stable yet, but it is very thoroughly tested both with automated tests and in production, so feel free to try it out and submit improvements on [github](https://github.com/Monnoroch/go-inject).

### Literature

- Motivation for [Guice](https://github.com/google/guice/wiki/Motivation), that explains what is DI, why do you want it and how to use it correctly
