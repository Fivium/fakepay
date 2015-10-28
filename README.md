# FakePay (a WorldPay Test Harness)

This is a simple Sinatra implementation of the WorldPay side of a payment. The idea is that this web application replaces the WorldPay test mode during development or system testing. You should still use WorldPay's test mode during user testing for a more formal proof that your application is working.

## Why did you create this?

WorldPay can operate in test or production mode, but unfortunately the URL that payment confirmation is sent to after the user completes (or cancels) a payment is only configurable once per "mode" in the WorldPay control panel, i.e one URL for test, one for production.

This is fine if you only have one "test" instance of your application, but if you have multiple test environments, you have to reconfigure the WorldPay end each time you want to perform end-to-end testing.

This simple web application mimmicks (some of) the WorldPay endpoint behaviour sufficiently to perform day-to-day development and integration testing.

## Installation

Fork [this repository](https://github.com/Fivium/fakepay) and then run Bundler to pull the required dependencies:

~~~
bundle install
~~~

Create a `conf/installations.yaml` file with one or more WorldPay installations; see `conf/installations.yaml.example` for inspiration. All properties are required.

~~~
- id: 123
  name: My first test installation
  md5_key: XXX
  callback_password: YYY 
  callback_url: http://127.0.0.1:80/worldpay-callback
- id: 456
  name: My second test installation
  md5_key: XXX
  callback_password: YYY 
  callback_url: http://127.0.0.1:80/worldpay-callback
~~~ 

These are essentially the same settings that you would configure via the WorldPay control panel.

## Use

To start up:

~~~
rackup config.ru
~~~

Assuming you've configured your installations.yaml, simply configure your development or test system to redirect it's WorldPay requests to

~~~
https://<your-server-here>/fakepay-transaction
~~~

You won't need any fake credit card details, and you should be able to see all the data that was sent with the request.

## Test

Verify the test harness is running by hitting the following URL:

~~~
/service-status
~~~

You should see the string "Up and running", with the current date/time for verification.