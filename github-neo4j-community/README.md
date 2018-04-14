# github-neo4j-community

Script to import data from the Neo4j community on GitHub

Does a search for `neo4j` in GitHub and imports all repositories.  For each repository it:

 * Recursively imports forks
 * Imports issues
 * Imports comments for issues
 * Imports comments on commits

Because it uses the `neo4apis-github` gem, associated users are imported for repositories, issues, and comments.  Also, a second pass is made to make a query for every user to get all data for each user.

`ActiveSupport::Cache::FileStore` is used to store a cache of all requests in a directory so that if the script fails it can pick up where it left off.

## How to run

    GITHUB_TOKEN=<token> NEO4J_URL=<neo4j server url> bundle exec ruby run.rb
