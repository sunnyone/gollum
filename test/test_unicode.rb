# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), "helper"))

def utf8(str)
  str.respond_to?(:force_encoding) ? str.force_encoding('utf-8') : str
end

context "Unicode Support" do
  setup do
    @path = cloned_testpath("examples/revert.git")
    @wiki = Gollum::Wiki.new(@path)
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  test "uri encode" do
    c = '한글'
    assert_equal '%ED%95%9C%EA%B8%80', encodeURIComponent(c)
    assert_equal '%ED%95%9C%EA%B8%80', CGI::escape(c)
  end

  test "create and read non-latin page with anchor" do
    @wiki.write_page("test", :markdown, "# 한글")

    page = @wiki.page("test")
    assert_equal Gollum::Page, page.class
    assert_equal "# 한글", utf8(page.raw_data)

    # markup.rb
    doc     = Nokogiri::HTML page.formatted_data
    h1s     = doc / :h1
    h1      = h1s.first
    anchors = h1 / :a
    assert_equal 1, h1s.size
    assert_equal 1, anchors.size
    assert_equal '#한글',  anchors[0]['href']
    assert_equal  '한글',  anchors[0]['id']
    assert_equal 'anchor', anchors[0]['class']
    assert_equal '',       anchors[0].text
  end

  test "create and read non-latin page with anchor 2" do
    @wiki.write_page("test", :markdown, "# \"La\" faune d'Édiacara")

    page = @wiki.page("test")
    assert_equal Gollum::Page, page.class
    assert_equal "# \"La\" faune d'Édiacara", utf8(page.raw_data)

    # markup.rb test: ', ", É
    doc     = Nokogiri::HTML page.formatted_data
    h1s     = doc / :h1
    h1      = h1s.first
    anchors = h1 / :a
    assert_equal 1, h1s.size
    assert_equal 1, anchors.size
    assert_equal %q(#%22La%22-faune-d'Édiacara), anchors[0]['href']
    assert_equal %q(%22La%22-faune-d'Édiacara),  anchors[0]['id']
    assert_equal 'anchor',                 anchors[0]['class']
    assert_equal '',                       anchors[0].text
  end

  test "unicode with existing format rules" do
    @wiki.write_page("test", :markdown, "# 한글")
    assert_equal @wiki.page("test").path, @wiki.page("test").path
  end
end

context "Frontend Unicode support" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath("examples/revert.git")
    @wiki = Gollum::Wiki.new(@path)
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, {})
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  test "creates korean page which contains korean content" do
    post "/create", :content => '한글 text', :page => "k",
      :format => 'markdown', :message => 'def'
    follow_redirect!
    assert last_response.ok?

    page = @wiki.page('k')
    assert_equal '한글 text', utf8(page.raw_data)
    assert_equal 'def', page.version.message
  end

  test "heavy use 1" do
    post "/create", :content => '한글 text', :page => "PG",
      :format => 'markdown', :message => 'def'
    follow_redirect!
    assert last_response.ok?

    @wiki.update_page(@wiki.page('PG'), nil, nil, '다른 text', {})
    page = @wiki.page('PG')
    assert_equal '다른 text', utf8(page.raw_data)

    post '/edit/PG', :page => 'PG', :content => '바뀐 text', :message => 'ghi'
    follow_redirect!
    assert last_response.ok?

    @wiki = Gollum::Wiki.new(@path)
    page = @wiki.page('PG')
    assert_equal '바뀐 text', utf8(page.raw_data)
    assert_equal 'ghi', page.version.message
  end

  test "heavy use 2" do
    post "/create", :content => '한글 text', :page => "k",
      :format => 'markdown', :message => 'def'
    follow_redirect!
    assert last_response.ok?

    @wiki.update_page(@wiki.page('k'), nil, nil, '다른 text', {})
    @wiki = Gollum::Wiki.new(@path)
    page = @wiki.page('k')
    assert_equal '다른 text', utf8(page.raw_data)

    post '/edit/' + CGI.escape('한글'), :page => 'k', :content => '바뀐 text',
      :format => 'markdown', :message => 'ghi'
    follow_redirect!
    assert last_response.ok?

    @wiki = Gollum::Wiki.new(@path)
    page = @wiki.page('k')
    assert_equal '바뀐 text', utf8(page.raw_data)
    assert_equal 'ghi', page.version.message
  end

  test 'opening a missing Japanese link preserves the create title' do
    @wiki.write_page('Links', :markdown, '[[日本語について]]')
    get '/Links'
    doc = Nokogiri::HTML(last_response.body)
    link = doc.css('a').find { |a| a.text == '日本語について' }
    assert_not_nil link
    get link['href']
    assert last_response.redirect?
    assert_equal 'http://example.org/create/' + encodeURIComponent('日本語について'),
      last_response.headers['Location']
    follow_redirect!
    assert last_response.ok?
    title = Nokogiri::HTML(last_response.body).at_css('input[name="page"]')
    assert_equal '日本語について', title['value']
  end

  test 'creates a Japanese page in a Japanese directory and follows its URL' do
    post '/create', :page => '日本語 入門', :path => '資料',
      :content => '日本語の本文', :format => 'markdown', :message => '作成'
    assert_equal 'http://example.org/' + encodeURIComponent('資料') + '/' +
      encodeURIComponent('日本語-入門'), last_response.headers['Location']
    follow_redirect!
    assert last_response.ok?
    page = @wiki.paged('日本語 入門', '資料')
    assert_not_nil page
    assert_equal '資料/日本語-入門.md', utf8(page.path)
    assert_equal '日本語の本文', utf8(page.raw_data)
    assert_equal '作成', utf8(page.version.message)
  end

  test 'edits and renames a Japanese page without transliteration' do
    @wiki.write_page('日本語について', :markdown, '最初の本文')
    post '/edit/' + encodeURIComponent('日本語について'),
      :page => '日本語について', :content => '更新した本文',
      :format => 'markdown', :message => '編集'
    follow_redirect!
    assert last_response.ok?

    post '/edit/' + encodeURIComponent('日本語について'),
      :page => '日本語について', :rename => '日本語の使い方',
      :content => '更新した本文', :format => 'markdown', :message => '改名'
    assert_equal 'http://example.org/' + encodeURIComponent('日本語の使い方'),
      last_response.headers['Location']
    follow_redirect!
    assert last_response.ok?
    @wiki.clear_cache
    assert_nil @wiki.page('日本語について')
    page = @wiki.page('日本語の使い方')
    assert_equal '日本語の使い方.md', utf8(page.path)
    assert_equal '更新した本文', utf8(page.raw_data)
  end

  test 'Japanese history and comparison redirects encode the path' do
    name = encodeURIComponent('資料') + '/' + encodeURIComponent('日本語')
    post '/compare/' + name, :versions => ['a' * 40]
    assert_equal 'http://example.org/history/' + name,
      last_response.headers['Location']

    post '/compare/' + name, :versions => ['b' * 40, 'a' * 40]
    assert_equal 'http://example.org/compare/' + name + '/' +
      'a' * 40 + '...' + 'b' * 40, last_response.headers['Location']
  end

  test 'preserves accented page names and special page names' do
    ['ééééé', '_Header', '_Footer', '_Sidebar'].each do |name|
      post '/create', :page => name, :path => '補助', :content => '本文',
        :format => 'markdown', :message => '作成'
      assert_equal 'http://example.org/' + encodeURIComponent('補助') + '/' + encodeURIComponent(name),
        last_response.headers['Location']
      @wiki.clear_cache
      assert_equal '補助/' + name + '.md', utf8(@wiki.paged(name, '補助', true).path)
    end
  end

  test 'does not override Stringex transliteration globally' do
    assert_equal 'eeeee', 'ééééé'.to_url
  end

  def app
    Precious::App
  end
end
