(ns stackoverflow-graphgist.core
  (:require [clojure.string :as str])
  (:require [clj-http.client :as client])
  (:require [cheshire.core :refer :all])
  (:require [clojurewerkz.neocons.rest :as nr]
            [clojurewerkz.neocons.rest.cypher :as cypher]
            [clojurewerkz.neocons.rest.nodes :as nodes]
            [clojurewerkz.neocons.rest.relationships :as neo_relationships])
  )


(defn stackoverflow-get-questions [page]
  (let [url (str "http://api.stackexchange.com/2.2/search?pagesize=100&page=" page "&order=desc&sort=activity&tagged=neo4j&site=stackoverflow")]
    ((client/get url) :body)))

(defn stackoverflow-get-answers [question-ids]
  (let [url (str "https://api.stackexchange.com/2.2/questions/" (str/join ";" question-ids) "/answers?order=desc&sort=activity&site=stackoverflow")]
    ((client/get url) :body)
  )
)

(defn merge-props [label props merge-prop neo4j-conn]
  (if-not (nil? (props merge-prop))
    (cypher/tquery neo4j-conn (str "MERGE (node:`" label "` {" merge-prop ": {props}." merge-prop "}) SET node:StackOverflow, node = {props} RETURN node") {"props" props})
    )
)

(defn import-user [user neo4j-conn]
  (let [keys (str/split "user_id reputation user_type accept_rate profile_image display_name link" #" ")]
    (merge-props "User" (select-keys user keys) "user_id" neo4j-conn)
  )
)

(defn import-tag [tag-text neo4j-conn]
  (merge-props "Tag" {"text" tag-text} "text" neo4j-conn)
)


(defn import-question [question neo4j-conn]
  (println "Called import-question")
  (let [keys (str/split "question_id score view_count creation_date last_activity_date title link is_answered answer_count" #" ")]
    (merge-props "Question" (select-keys question keys) "question_id" neo4j-conn)

    (import-user (question "owner") neo4j-conn)
    (cypher/tquery neo4j-conn "MATCH (q:Question {question_id: {question_id}}), (u:User {user_id: {user_id}}) CREATE u-[:ASKED]->q" {:question_id (question "question_id") :user_id ((question "owner") "user_id")})

    (dorun
      (for [tag-text (question "tags")]
        (do
          (import-tag tag-text neo4j-conn)
          (cypher/tquery neo4j-conn "MATCH (q:Question {question_id: {question_id}}), (t:Tag {text: {tag_text}}) CREATE q<-[:TAGS]-t" {:question_id (question "question_id") :tag_text tag-text})
        )
      )
    )
  )
)

(defn import-answer [answer neo4j-conn]
  (println "Called import-answer")
  (let [keys (str/split "answer_id creation_date is_accepted last_activity_date question_id score" #" ")]
    (merge-props "Answer" (select-keys answer keys) "answer_id" neo4j-conn)
    
    (import-user (answer "owner") neo4j-conn)
    (cypher/tquery neo4j-conn "MATCH (a:Answer {answer_id: {answer_id}}), (u:User {user_id: {user_id}}) CREATE u-[:PROVIDED]->a" {:answer_id (answer "answer_id") :user_id ((answer "owner") "user_id")})

    (cypher/tquery neo4j-conn "MATCH (q:Question {question_id: {question_id}}), (a:Answer {answer_id: {answer_id}}) CREATE a-[:ANSWERS]->q" {:answer_id (answer "answer_id") :question_id (answer "question_id")})
  )
)


(defn import-page [page-number neo4j-conn]
  (println (str "Importing page: " page-number))
  (let [data (parse-string (stackoverflow-get-questions page-number))
              questions (data "items")
              has-more (data "has_more")
              question-ids (map #(%1 "question_id") questions)
              answers ((parse-string (stackoverflow-get-answers question-ids)) "items")]
      (doseq [question questions] (import-question question neo4j-conn))
      (doseq [answer answers]     (import-answer answer neo4j-conn))
      has-more
    )
  )

(defn -main
  [& args]

  (let [neo4j-conn  (nr/connect "http://localhost:7474/db/data/")]
    (cypher/tquery neo4j-conn "CREATE CONSTRAINT ON (q:Question) ASSERT q.question_id IS UNIQUE")
    (cypher/tquery neo4j-conn "CREATE CONSTRAINT ON (a:Answer) ASSERT a.answer_id IS UNIQUE")
    (cypher/tquery neo4j-conn "CREATE CONSTRAINT ON (u:User) ASSERT u.user_id IS UNIQUE")
    (cypher/tquery neo4j-conn "CREATE CONSTRAINT ON (t:Tag) ASSERT t.text IS UNIQUE")

    (cypher/tquery neo4j-conn "MATCH n OPTIONAL MATCH n-[r]-() DELETE n, r")

    (take-while #(import-page %1 neo4j-conn) (map #(inc %1) (range)))

  )
)

