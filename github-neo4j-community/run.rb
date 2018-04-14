require 'pry'
require 'github_api'
require 'neo4apis/github'
require 'active_support'
require 'neo4j'

NEO4J = Neo4j::Session.open(:server_db, ENV['NEO4J_URL'])

neo4apis_github = Neo4Apis::Github.new(NEO4J, relationship_transform: :upcase)


require 'github_api/request'
require 'faraday_middleware'

# This is a bit of an ugly monkey patch because I was unable to get
# the github_api's `stack` faraday middleware integration to work
module Github
  class Middleware
    def self.default(options = {})
      api = options[:api]
      proc do |builder|
        builder.use Github::Request::Jsonize
        builder.use Faraday::Request::Multipart
        builder.use Faraday::Request::UrlEncoded
        builder.use Github::Request::OAuth2, api.oauth_token if api.oauth_token?
        builder.use Github::Request::BasicAuth, api.authentication if api.basic_authed?

        builder.use Faraday::Response::Logger if ENV['DEBUG']
        unless options[:raw]
          builder.use Github::Response::Mashify
          builder.use Github::Response::Jsonize
        end
        builder.use Github::Response::RaiseError

        # LINES INSERTED BY ME
        store = ActiveSupport::Cache::FileStore.new 'cache', expires_in: (3600 * 24 * 365)
        builder.use FaradayMiddleware::Caching, store, ignore_params: %w[access_token]
        # END LINES INSERTED BY ME

        builder.adapter options[:adapter]
      end
    end
  end # Middleware
end # Github

#ActiveSupport::Cache::Store.logger = Logger.new(STDOUT)


github_client = Github.new(oauth_token: ENV['GITHUB_TOKEN'])#, adapter: :excon)

def user_and_repo(html_url)
  html_url.match(/github\.com\/([^\/]+)\/([^\/]+)/)[1,2]
end

def import_repository(neo4apis_github, github_client, repository)
  neo4apis_github.import(:Repository, repository).tap do |repo_node|
    puts 'Importing forks...'

    user, repo = user_and_repo(repository.html_url)

    import_languages!(neo4apis_github, github_client, user, repo, repo_node)

    github_client.repositories.forks.list(user: user, repo: repo).each_page do |fork_repositories|
      fork_repositories.each do |fork_repository|
        fork_repository_node = import_repository(neo4apis_github, github_client, fork_repository)

        neo4apis_github.add_relationship(:FORKED_FROM, fork_repository_node, repo_node) if fork_repository_node
      end
    end
  end
rescue Github::Error::NotFound
  nil
end

def import_contributors!(neo4apis_github, github_client, user, repo, repo_node)
  github_client.repos.contributors(user: user, repo: repo).each_page do |contributors|
    next if contributors.size.zero?

    contributors.each do |contributor|
      contributor_node = neo4apis_github.import :User, contributor

      neo4apis_github.add_relationship(:CONTRIBUTED_TO, contributor_node, repo_node)
    end
  end
rescue Github::Error::NotFound
  nil
end

Neo4Apis::Github.uuid :Language, :name
Neo4Apis::Github.importer :Language do |language|
  add_node :Language, OpenStruct.new(name: language), [:name]
end
  
def import_languages!(neo4apis_github, github_client, user, repo, repo_node)
  github_client.repositories.languages(user: user, repo: repo).each do |language, byte_count|
    language_node = neo4apis_github.import :Language, language

    neo4apis_github.add_relationship(:USES_LANGUAGE, repo_node, language_node, byte_count: byte_count)
  end
end

def import_issues!(neo4apis_github, github_client, user, repo, repo_node, issue_nodes_by_number)
  puts 'Importing issues...'
  github_client.issues.list(user: user, repo: repo, filter: 'all', state: 'all', per_page: 100).each_page do |issues|
    issues.each do |issue|
      issue_node = neo4apis_github.import :Issue, issue

      issue_nodes_by_number[issue.number.to_i] = issue_node

      neo4apis_github.add_relationship(:HAS_ISSUE, repo_node, issue_node)
    end
  end
rescue Github::Error::NotFound
  nil
end

def import_issue_comments(neo4apis_github, github_client, user, repo, issue_nodes_by_number)
  puts 'Importing issue comments...'
  github_client.issues.comments.list(user: user, repo: repo, per_page: 100).each_page do |comments|
    comments.each do |comment|
      comment_node = neo4apis_github.import :Comment, comment

      issue_number = comment.issue_url.match(/\/(\d+)\/?/)[1].to_i
      issue_node = issue_nodes_by_number[issue_number]
      neo4apis_github.add_relationship(:COMMENTS_ON, comment_node, issue_node) if comment_node && issue_node
    end
  end
rescue Github::Error::NotFound
  nil
end

def import_repository_comments(neo4apis_github, github_client, user, repo, repo_node)
  puts 'Importing repository comments...'
  github_client.repositories.comments.list(user: user, repo: repo, per_page: 100).each_page do |comments|
    comments.each do |comment|
      comment_node = neo4apis_github.import :Comment, comment

      if comment.commit_id
        begin
          commit = github_client.repositories.commits.get(user: user, repo: repo, sha: comment.commit_id)

          commit_node = neo4apis_github.import :Commit, commit

          neo4apis_github.add_relationship(:COMMENTS_ON, comment_node, commit_node)

          neo4apis_github.add_relationship(:IN_REPOSITORY, commit_node, repo_node)
        rescue Github::Error::NotFound
          puts "Didn't find commit #{comment.commit_id}"
        end
      end
    end
  end
rescue Github::Error::NotFound
  nil
end

def populate_users(github_client)
  NEO4J.query('MATCH (u:User:GitHub) WHERE u.created_at IS NULL RETURN u').map(&:u).each do |user|
    user_data = github_client.users.get(user: user.props[:login])

    fields = %w(name company blog location email hireable bio created_at updated_at)

    attribute_list = (fields & user_data.keys.map(&:to_s)).map do |field|
      "u.#{field} = {#{field}}"
    end.join(', ')

    NEO4J.query("MATCH (u:User:GitHub) WHERE ID(u) = {user_id} SET #{attribute_list}", user_data.to_hash.merge(user_id: user.neo_id))
  end
end

neo4apis_github.batch do
  github_client.search.repositories('neo4j', per_page: 100).each_page do |search_page|
    puts 'Searching for neo4j repos...'
    search_page.items.each do |repository|
      puts "Importing repository #{repository.html_url}..."
      repo_node = import_repository(neo4apis_github, github_client, repository)

      user, repo = user_and_repo(repository.html_url)
      issue_nodes_by_number = {}
      import_contributors!(neo4apis_github, github_client, user, repo, repo_node)
      import_issues!(neo4apis_github, github_client, user, repo, repo_node, issue_nodes_by_number)
      import_issue_comments(neo4apis_github, github_client, user, repo, issue_nodes_by_number)
      import_repository_comments(neo4apis_github, github_client, user, repo, repo_node)

      populate_users(github_client)
    end
  end
end

