


USE dvd_rentals;
GO


-- Creating Title Function
CREATE FUNCTION [dbo].[Title] (@inStr [VARCHAR](8000))
RETURNS VARCHAR(8000)
AS
BEGIN
    DECLARE @outStr VARCHAR(8000) = LOWER(@inStr),
            @char CHAR(1),
            @alphanum BIT = 0,
            @len INT = LEN(@inStr),
            @pos INT = 1;

    -- Iterate through all characters in the input string
    WHILE @pos <= @len
    BEGIN

        -- Get the next character
        SET @char = SUBSTRING(@inStr, @pos, 1);

        -- If the position is first, or the previous character is not alphanumeric
        -- convert the current character to upper case
        IF @pos = 1
           OR @alphanum = 0
            SET @outStr = STUFF(@outStr, @pos, 1, UPPER(@char));

        SET @pos = @pos + 1;

        -- Define if the current character is non-alphanumeric
        IF ASCII(@char) <= 47
           OR (ASCII(@char)
           BETWEEN 58 AND 64
              )
           OR (ASCII(@char)
           BETWEEN 91 AND 96
              )
           OR (ASCII(@char)
           BETWEEN 123 AND 126
              )
            SET @alphanum = 0;
        ELSE
            SET @alphanum = 1;
    END
    RETURN @outStr;
END
GO

-- Creat a Table which we will use for our need couple of times
DROP TABLE IF EXISTS movie_table;
WITH joined_table
AS (SELECT rental.customer_id,
           rental.rental_id,
           film.film_id,
           film.title,
           category.name as movie_genre
    FROM rental
        LEFT JOIN inventory
            ON rental.inventory_id = inventory.inventory_id
        LEFT JOIN film
            ON inventory.film_id = film.film_id
        LEFT JOIN film_category
            ON film.film_id = film_category.film_id
        LEFT JOIN category
            ON film_category.category_id = category.category_id
   )
SELECT *
INTO movie_table
FROM joined_table;


SELECT TOP (5) * FROM movie_table;
GO


--1) Identify top 2 categories for each customer based off their past rental history
DROP TABLE IF EXISTS top_category;
WITH category_rank
AS (SELECT customer_id,
           movie_genre,
           count(rental_id) as total_rent,
           DENSE_RANK() OVER (PARTITION BY customer_id
                              ORDER BY COUNT(rental_id) DESC,
                                       movie_genre DESC
                             ) as genre_rank
    FROM movie_table
    GROUP BY customer_id,
             movie_genre
   )
SELECT *
INTO top_category
FROM category_rank
WHERE genre_rank <= 2;

SELECT TOP (4) * FROM top_category ORDER BY customer_id;

GO

--- Reccomend Movie as per Top 2 category/genre
-- For each customer recommend up to 3 popular unwatched films for each category
DROP TABLE IF EXISTS movie_recommendations;
WITH genre_recommendations
AS (SELECT top_category.customer_id,
           top_category.movie_genre,
           top_category.genre_rank,
           rental_count.film_id,
           rental_count.title,
           rental_count.total_rent,
           DENSE_RANK() OVER (PARTITION BY top_category.customer_id,
                                           top_category.genre_rank
                              ORDER BY rental_count.total_rent,
                                       rental_count.title
                             ) as recomendation_order
    FROM
    (
        SELECT film_id,
               title,
               movie_genre,
               COUNT(film_id) AS total_rent
        FROM movie_table
        GROUP BY film_id,
                 title,
                 movie_genre
    ) AS rental_count
        INNER JOIN top_category
            ON top_category.movie_genre = rental_count.movie_genre
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM
        (SELECT customer_id, film_id FROM movie_table) AS movie_watched
        WHERE movie_watched.customer_id = top_category.customer_id
              AND movie_watched.film_id = rental_count.film_id
    )
   )
SELECT customer_id,
       movie_genre,
       genre_rank,
       dbo.Title(title) AS movie,
       film_id,
       recomendation_order,
       total_rent AS total_watched
INTO movie_recommendations
FROM genre_recommendations
WHERE recomendation_order <= 3
ORDER BY customer_id,
         genre_rank,
         total_rent,
         recomendation_order;

SELECT TOP(6) * FROM movie_recommendations ORDER BY customer_id, genre_rank;
GO




-- Genre Count
DROP TABLE IF EXISTS genre_count;
SELECT *
INTO genre_count
FROM
(
    SELECT customer_id,
           movie_genre,
           COUNT(rental_id) as total_rent
    FROM movie_table
    GROUP BY customer_id,
             movie_genre
) as genre_count;
GO

--- CATEGORY RANK by Percentile - FOr Top  1 category Insight
DROP TABLE IF EXISTS category_percentile;
SELECT *  INTO category_percentile FROM ( SELECT customer_id,
  movie_genre,
  total_rent,
  CASE
    WHEN ROUND(100 * percentile,0) = 0 THEN 1
    ELSE ROUND(100 * percentile,0)
  END AS percentile  
  FROM
(SELECT 
	top_category.customer_id,top_category.total_rent,top_category.movie_genre AS top_genre,
	genre_count.movie_genre, top_category.genre_rank,
	PERCENT_RANK() OVER (PARTITION BY genre_count.movie_genre ORDER BY genre_count.total_rent DESC) AS percentile 
	FROM top_category 
		RIGHT JOIN genre_count ON top_category.customer_id = genre_count.customer_id) AS p_rank
		
		WHERE
  genre_rank = 1
  AND top_genre = movie_genre) AS best_category_percentile	;


SELECT TOP(5) * FROM genre_count;
SELECT TOP(5) * FROM category_percentile;

/*
**_3.1Generate 1st category insights that includes:
	- How many total films have they watched in their top category?
	- How many more films has the customer watched compared to the average DVD Rental Co customer?
	- How does the customer rank in terms of the top X% compared to all other customers in this film category?_**
*/
DROP TABLE IF EXISTS first_category_insights;
SELECT *
INTO first_category_insights
FROM
(
    SELECT category_percentile.customer_id,
           category_percentile.movie_genre,
           category_percentile.total_rent,
           category_percentile.total_rent - avg_category.avg_rent AS average_comparison,
           category_percentile.percentile
    FROM
    (
        SELECT movie_genre,
               floor(avg(total_rent)) AS avg_rent
        FROM genre_count
        GROUP BY movie_genre
    ) AS avg_category
        LEFT JOIN category_percentile
            ON category_percentile.movie_genre = avg_category.movie_genre
) first_category_insight;


SELECT TOP (5) * FROM first_category_insights ORDER BY customer_id;

GO

/*
4) Generate 2nd insights that includes:
	- How many total films has the customer watched in this category?
	- What proportion of each customer’s total films watched does this count make?
*/
DROP TABLE IF EXISTS second_category_insights;
SELECT *
INTO second_category_insights
FROM
(
    SELECT top_category.customer_id,
           top_category.movie_genre,
           top_category.total_rent,
           ROUND(100 * cast(top_category.total_rent AS float) / total_counts.total_rent, 2) AS percentage
    FROM
    (
        SELECT customer_id,
               sum(total_rent) as total_rent
        FROM genre_count
        GROUP BY customer_id
    ) AS total_counts
        RIGHT JOIN top_category
            ON total_counts.customer_id = top_category.customer_id
    WHERE top_category.genre_rank = 2
) AS second_category_insight;

SELECT TOP (5)
    *
FROM second_category_insights
ORDER BY customer_id;

GO


-- Actor Based Insight
-- Lets create a table and call it actor info.
-- Creat a Table which we will use for our need couple of times
DROP TABLE IF EXISTS actor_info;
WITH joined_table
AS (SELECT rental.customer_id,
           rental.rental_id,
           rental.rental_date,
           film.film_id,
           film.title,
           actor.actor_id,
           actor.first_name,
           actor.last_name
    FROM rental
        LEFT JOIN inventory
            ON rental.inventory_id = inventory.inventory_id
        LEFT JOIN film
            ON inventory.film_id = film.film_id
        LEFT JOIN film_actor
            ON film.film_id = film_actor.film_id
        LEFT JOIN actor
            ON film_actor.actor_id = actor.actor_id
   )
SELECT *
INTO actor_info
FROM joined_table;


--4.1 Which actor has featured in the customer’s rental history the most?

DROP TABLE IF EXISTS top_actors;
WITH top_actor_counts AS (
  SELECT customer_id,actor_id,first_name,last_name, COUNT(*) AS total_rent,MAX(rental_date) AS latest_rental_date
  FROM actor_info GROUP BY customer_id, actor_id, first_name, last_name),
ranked_actor_counts AS (
  SELECT
    top_actor_counts.*,
    DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY total_rent DESC,latest_rental_date DESC,first_name,
        last_name ) AS actor_rank FROM top_actor_counts)
SELECT
  customer_id,
  actor_id,
  first_name,
  last_name,
  total_rent into top_actors
FROM ranked_actor_counts
WHERE actor_rank = 1;

SELECT TOP (5) * FROM top_actors ORDER BY customer_id;
GO


-- Actor film Exclusion will be used to suggest those movies which has been watched by customer yet.
DROP TABLE IF EXISTS actor_film_exclusions;
SELECT *
INTO actor_film_exclusions
FROM
(
    (SELECT DISTINCT
         customer_id,
         film_id
     FROM movie_table)
    UNION
    (SELECT DISTINCT
         customer_id,
         film_id
     FROM movie_recommendations)
) AS actor_film_exclusions;


SELECT *
FROM actor_film_exclusions;

-- Actor Film Counts
DROP TABLE IF EXISTS actor_film_counts;
SELECT DISTINCT
    actor_info.film_id,
    actor_info.actor_id,
    actor_info.title,
    film_counts.rental_count
INTO actor_film_counts
FROM
(
    SELECT film_id,
           COUNT(DISTINCT rental_id) AS rental_count
    FROM actor_info
    GROUP BY film_id
) AS film_counts
    LEFT JOIN actor_info
        ON actor_info.film_id = film_counts.film_id;
GO



-- Actor Recommendation
DROP TABLE IF EXISTS actor_recommendations;

SELECT *
INTO actor_recommendations
FROM
(
    SELECT top_actors.customer_id,
           concat(top_actors.first_name, ' ', top_actors.last_name) AS name,
           top_actors.total_rent,
           actor_film_counts.title,
           actor_film_counts.film_id,
           actor_film_counts.actor_id,
           DENSE_RANK() OVER (PARTITION BY top_actors.customer_id
                              ORDER BY actor_film_counts.rental_count DESC,
                                       actor_film_counts.title
                             ) AS actor_rank
    FROM top_actors
        INNER JOIN actor_film_counts
            ON top_actors.actor_id = actor_film_counts.actor_id
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM actor_film_exclusions
        WHERE actor_film_exclusions.customer_id = top_actors.customer_id
              AND actor_film_exclusions.film_id = actor_film_counts.film_id
    )
) AS actor_recommendations
WHERE actor_rank <= 3;

SELECT TOP(5) * FROM actor_recommendations;
GO


-- Final Result
DROP TABLE IF EXISTS final_output;
WITH first_category
AS (SELECT customer_id,
           movie_genre,
           CONCAT(
                     'You''ve watched ',
                     total_rent,
                     ' ',
                     movie_genre,
                     ' films, that''s ',
                     average_comparison,
                     ' more than the DVD Rental Co average and puts you in the top ',
                     percentile,
                     '% of ',
                     movie_genre,
                     ' gurus!'
                 ) AS insight
    FROM first_category_insights
   ),
     second_category
AS (SELECT customer_id,
           movie_genre,
           CONCAT(
                     'You''ve watched ',
                     total_rent,
                     ' ',
                     movie_genre,
                     ' films making up ',
                     percentage,
                     ' of your entire viewing history!'
                 ) AS insight
    FROM second_category_insights
   ),
     top_actor
AS (SELECT customer_id,
           CONCAT(dbo.Title(first_name), ' ', dbo.Title(last_name)) AS actor_name,
           CONCAT(
                     'You''ve watched ',
                     total_rent,
                     ' films featuring ',
                     dbo.Title(first_name),
                     ' ',
                     dbo.Title(last_name),
                     '! Here are some other films ',
                     dbo.Title(first_name),
                     ' stars in that might interest you!'
                 ) AS insight
    FROM top_actors
   ),
     adjusted_title_case_category_recommendations
AS (SELECT customer_id,
           dbo.Title(movie) AS title,
           genre_rank,
           recomendation_order
    FROM movie_recommendations
   ),
     wide_category_recommendations
AS (SELECT customer_id,
           MAX(   CASE
                      WHEN genre_rank = 1
                           AND recomendation_order = 1 THEN
                          title
                  END
              ) AS genre_1_movie_1,
           MAX(   CASE
                      WHEN genre_rank = 1
                           AND recomendation_order = 2 THEN
                          title
                  END
              ) AS genre_1_movie_2,
           MAX(   CASE
                      WHEN genre_rank = 1
                           AND recomendation_order = 3 THEN
                          title
                  END
              ) AS genre_1_movie_3,
           MAX(   CASE
                      WHEN genre_rank = 2
                           AND recomendation_order = 1 THEN
                          title
                  END
              ) AS genre_2_movie_1,
           MAX(   CASE
                      WHEN genre_rank = 2
                           AND recomendation_order = 2 THEN
                          title
                  END
              ) AS genre_2_movie_2,
           MAX(   CASE
                      WHEN genre_rank = 2
                           AND recomendation_order = 3 THEN
                          title
                  END
              ) AS genre_2_movie_3
    FROM adjusted_title_case_category_recommendations
    GROUP BY customer_id
   ),
     adjusted_title_case_actor_recommendations
AS (SELECT customer_id,
           dbo.title(title) AS title,
           actor_rank
    FROM actor_recommendations
   ),
     wide_actor_recommendations
AS (SELECT customer_id,
           MAX(   CASE
                      WHEN actor_rank = 1 THEN
                          title
                  END
              ) AS actor_movie_1,
           MAX(   CASE
                      WHEN actor_rank = 2 THEN
                          title
                  END
              ) AS actor_movie_2,
           MAX(   CASE
                      WHEN actor_rank = 3 THEN
                          title
                  END
              ) AS actor_movie_3
    FROM adjusted_title_case_actor_recommendations
    GROUP BY customer_id
   )
SELECT t1.customer_id AS id,
       t1.movie_genre AS genre_1st,
       t4.genre_1_movie_1,
       t4.genre_1_movie_2,
       t4.genre_1_movie_3,
       t2.movie_genre AS second_genre,
       t4.genre_2_movie_1,
       t4.genre_2_movie_2,
       t4.genre_2_movie_3,
       t3.actor_name AS actor,
       t5.actor_movie_1,
       t5.actor_movie_2,
       t5.actor_movie_3,
       t1.insight AS insight_genre_1,
       t2.insight AS insight_genre_2,
       t3.insight AS insight_actor
into final_output
FROM first_category AS t1
    INNER JOIN second_category AS t2
        ON t1.customer_id = t2.customer_id
    INNER JOIN top_actor t3
        ON t1.customer_id = t3.customer_id
    INNER JOIN wide_category_recommendations AS t4
        ON t1.customer_id = t4.customer_id
    INNER JOIN wide_actor_recommendations AS t5
        ON t1.customer_id = t5.customer_id;

SELECT TOP (5)
    *
FROM final_output;
GO

