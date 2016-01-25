require 'webhook_multiplexer'

RSpec.describe WebhookMultiplexer do
  subject(:app) { described_class }


  context 'GET call' do
    before { get('/foo') }

    it 'returns 200' do
      expect(last_response.status).to eq(200)
    end

    it 'has body' do
      expect(last_response.body).to eq('payload delivered to 0 locations')
    end

    it 'made no requests' do
      expect(WebMock).not_to have_requested(:any, //)
    end

    context 'configured to echo api', env: { 'WEBHOOK_MULTIPLEXER_URLS' => 'http://echo-api.3scale.net' } do
      it 'returns 200' do
        expect(last_response.status).to eq(200)
      end

      it 'has body' do
        expect(last_response.body).to eq('payload delivered to 1 locations')
        expect(a_request(:get, 'http://echo-api.3scale.net/foo')).to have_been_made.once
      end
    end

    context 'configured to several apis', env: { 'WEBHOOK_MULTIPLEXER_URLS' => 'http://echo-api.3scale.net;https://echo-api.3scale.net' } do
      it 'has body' do
        expect(last_response.body).to eq('payload delivered to 2 locations')
      end

      it 'makes requests' do
        expect(a_request(:get, 'http://echo-api.3scale.net/foo')).to have_been_made.once
        expect(a_request(:get, 'https://echo-api.3scale.net/foo')).to have_been_made.once
      end
    end
  end

  context 'does not mangle the url', env: { 'WEBHOOK_MULTIPLEXER_URLS' => 'http://echo-api.3scale.net/foo' } do
    before { get('/') }

    it 'makes requests' do
      expect(a_request(:get, 'http://echo-api.3scale.net/foo')).to have_been_made.once
    end
  end

  context 'has complicated configuration', env: {
      'WEBHOOK_MULTIPLEXER_URLS' => [
          'GET,http://echo-api.3scale.net/api/v1,Authorization: Bearer foobarbaz',
          'PUT,https://echo-api.3scale.net/api/v2/echo,Authorization: Bearer tududu,Content-Type: application/xml'
      ].join(';')
    } do

    before { post('/foo', {'boo' => 'bar'}, {'HTTP_FORWARDED_FOR' => '8.8.8.8'}) }
    before { last_request.extend(WebhookMultiplexer::RequestHeaders) }

    it 'makes requests' do
      expect(last_request.headers).to eq('FORWARDED_FOR' => '8.8.8.8', 'HOST' => 'example.org', 'COOKIE' => '')

      expect(a_request(:get, 'http://echo-api.3scale.net/api/v1/foo')
                 .with(headers: last_request.headers.merge('HOST' => 'echo-api.3scale.net')
                     .merge('AUTHORIZATION' => 'Bearer foobarbaz')))
          .to have_been_made.once

      expect(a_request(:put, 'https://echo-api.3scale.net/api/v2/echo/foo')
                 .with(headers:  {'AUTHORIZATION' => 'Bearer tududu'}))
          .to have_been_made.once
    end
  end

  context 'GET /bar?query=foo&other=bar', env: { 'WEBHOOK_MULTIPLEXER_URLS' => 'http://echo-api.3scale.net' } do
    before { get('/bar?query=foo&other=bar') }
    before { last_request.extend(WebhookMultiplexer::RequestHeaders) }

    it 'makes requests' do

      expect(a_request(:get, 'http://echo-api.3scale.net/bar?query=foo&other=bar')
                 .with(headers: last_request.headers.merge('HOST' => 'echo-api.3scale.net')))
          .to have_been_made.once
    end
  end


  context 'GET /bar?query=foo&other=bar', env: { 'WEBHOOK_MULTIPLEXER_URLS' => 'http://echo-api.3scale.net' } do
    before { get('/bar?query=foo&other=bar') }
    before { last_request.extend(WebhookMultiplexer::RequestHeaders) }

    it 'makes requests' do

      expect(a_request(:get, 'http://echo-api.3scale.net/bar?query=foo&other=bar')
                 .with(headers: last_request.headers.merge('HOST' => 'echo-api.3scale.net')))
          .to have_been_made.once
    end
  end

  context '#request_has_body?' do
    it 'returns false for GET' do
      expect(subject.request_has_body?('GET')).to be(false)
    end

    it 'returns true for POST' do
      expect(subject.request_has_body?('POST')).to be(true)
    end

    it 'returns nil for INVALID' do
      expect(subject.request_has_body?('INVALID')).to be_nil
    end
  end

  context 'failure', env: {
      'WEBHOOK_MULTIPLEXER_URLS' => (['http://echo-api.3scale.net'] * 4 + ['https://echo-api.3scale.net']).join(';')
    } do
    it 'reports failed calls' do
      stub_request(:any, 'http://echo-api.3scale.net').
          to_return(:status => [500, 'Internal Server Error']).then.
          to_timeout.then.
          to_return(:status => [500, 'Internal Server Error']).then.
          to_return(status: 200)

      get('/')

      expect(last_response.body).to eq('payload delivered to 2 locations, 3 errors (500, timeout, 500)')
    end
  end
end
