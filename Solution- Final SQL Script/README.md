# Marketing_Analytics_-DVD_Rental_Store-


At First, we will create a function and Join some tables.
<details><summary> 1. Create a function to transform all movie titles and actor names into title cases.</summary>

```sql
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
    WHILE @pos <= @len BEGIN
 
      -- Get the next character
      SET @char = SUBSTRING(@inStr, @pos, 1);
 
      -- If the position is first, or the previous character is not alphanumeric
      -- convert the current character to upper case
      IF @pos = 1 OR @alphanum = 0
        SET @outStr = STUFF(@outStr, @pos, 1, UPPER(@char));
 
      SET @pos = @pos + 1;
 
      -- Define if the current character is non-alphanumeric
      IF ASCII(@char) <= 47 OR (ASCII(@char) BETWEEN 58 AND 64) OR
	  (ASCII(@char) BETWEEN 91 AND 96) OR (ASCII(@char) BETWEEN 123 AND 126)
	  SET @alphanum = 0;
      ELSE
	  SET @alphanum = 1;
    END
   RETURN @outStr;		   
  END
GO
```

</details>

<br>
<details>
<summary> 
2) Create a Movie Table to get movie suggestions </br>
    Here we will perform a <b>LEFT JOIN</b> to create a new table call <b> movie_table</b> from </br>
     i) <i>inventory</i> table,</br>
    ii) <i>film</i> table,</br>
    iii) <i>film_category</i> table and </br>
    iv) <i>category</i> table. </br>
</summary>

```sql

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

SELECT TOP (5) * FROM movie_table

GO

```

> **Results**

|customer_id|	rental_id|	film_id	title|	movie_genre|
|---|---|---|---|
|431|	4863|	1|	ACADEMY DINOSAUR	|Documentary|
|518|	11433|	1|	ACADEMY DINOSAUR	|Documentary|
|279|	14714|	1|	ACADEMY DINOSAUR	|Documentary|
|411|	972|	1|	ACADEMY DINOSAUR	|Documentary|
|170|	2117|	1|	ACADEMY DINOSAUR	|Documentary|

---

</details>


---


**_1)Identify top 2 categories for each customer based off their past rental history._**

---

```sql

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

```

> **Results**

|customer_id|	movie_genre|	total_rent|	genre_rank|
|---|---|---|---|
|1|	Comedy|	5|	2|
|1|	Classics|	6|	1|
|2|	Classics|	4|	2|
|2|	Sports|	5|	1|

> Explanation: For customer_id 1, Top two categories are Comedy and Classic while for customer_id 2 it is Classic and Sports

---

**_2)For each customer recommend up to 3 popular unwatched films for each category._**

---

```sql

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
       title AS movie,
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

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127764470-6a158608-8149-45e5-88d7-4453500c5dd4.png)

> For customer_id 1, We will suggest Sling Luke, Extraordinary Conquerer, Conspiracy Spirit from the classic genre and>  Connection Microcosmos, Rushmore Mermaid, Freedom Cleopatra from comedy.

---

<details>
<summary> 
Let's create two more tables.<br>
  * Count total movie rent as per genre : genre_count <br>
  * Calculate the Percentile of Each Category : category_percentile <br>
 Both will be used to get the insights of the First category/Genre and Second Category/Genre.<br>
</summary>

---
  
```sql

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

-- Create TABLE category Percentile
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

```

> **Results**
  
![image](https://user-images.githubusercontent.com/49762426/127764900-20204f76-86fa-4c36-bbc7-b3837699cdea.png)
  
---

</details>


---

**_3.1Generate 1st category insights that includes:<br>
	- How many total films have they watched in their top category?<br>
	- How many more films has the customer watched compared to the average DVD Rental Co customer?<br>
	- How does the customer rank in terms of the top X% compared to all other customers in this film category?_**

---

```sql

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

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127765104-fc96e654-1b8d-4590-bde8-2bc541d83e08.png)

##### For customer 1, watched 6 Classics films, that’s 4 more than the DVD Rental Coverage and puts customer 1 in the top 1% of Classics genre!

---

**_4) Generate 2nd insights that includes:<br>
	- How many total films has the customer watched in this category?<br>
	- What proportion of each customer’s total films watched does this count make?_**

---

```sql

DROP TABLE IF EXISTS second_category_insights;
SE<br><br>LECT *
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

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127765185-a27d538b-4f76-47b9-ade6-4748d0a1f7e4.png)

##### For customer 1, watched 5 Classics films, which is around 16% of his/her entire rental history!

---
### Actor Insights
<details>
<summary> 
* Let's creat a new table and name it as <b> actor_info.</b><br>  * To create this movie_info we will use <i><b>i) rental </i></b> table , <i><b>ii) inventory </i></b>table, <i><b>iii) film</i></b> table, <i><b>iv) film_actor </i></b> table and <i><b>v) actor </i></b> table <br>  
  * We will perform a LEFT JOIN to join all the above-mentioned tables. <br>
</summary> 
  
```sql

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
  
```  
  
</details>  

---
  
  **_4.1) Which actor has featured in the customer’s rental history the most?<br>
     4.2) How many films featuring this actor has been watched by the customer?_**

---

```sql

DROP TABLE IF EXISTS top_actors;
WITH top_actor_counts
AS (SELECT customer_id,
           actor_id,
           first_name,
           last_name,
           COUNT(*) AS total_rent,
           MAX(rental_date) AS latest_rental_date
    FROM actor_info
    GROUP BY customer_id,
             actor_id,
             first_name,
             last_name
   ),
     ranked_actor_counts
AS (SELECT top_actor_counts.*,
           DENSE_RANK() OVER (PARTITION BY customer_id
                              ORDER BY total_rent DESC,
                                       latest_rental_date DESC,
                                       first_name,
                                       last_name
                             ) AS actor_rank
    FROM top_actor_counts
   )
SELECT customer_id,
       actor_id,
       first_name,
       last_name,
       total_rent
into top_actors
FROM ranked_actor_counts
WHERE actor_rank = 1;

SELECT TOP (5)
    *
FROM top_actors
ORDER BY customer_id;
GO

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127765649-ae67bb5a-fa4e-48a4-8abb-9b2e0ce6a4d0.png)

---

<details>
<summary>
Before we recommend the top 3 films based on top actors which have not been watched by the customer, we need to create two more tables<br> <b>
  i) actor_film_exclusions</b><br> and
  ii) <b>actor_film_counts:</b> It will generate aggregated total rental counts across all customers. 
</summary>

```sql
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


-- Actor film_counts

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
    
```
  
</details>

---

**_1)Actor Recommendation:<br>
      * What are the top 3 recommendations featuring this same actor which have not been watched by the customer?_**

---

```sql

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

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127766496-4c2cc2ff-c704-4b64-b35f-51470a1f020f.png)

---

### Final Output

---

```sql
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
SELECT t1.customer_id,
       t1.movie_genre AS first_genre,
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

```

> **Results**

![image](https://user-images.githubusercontent.com/49762426/127767169-cc90a4a6-effc-4edf-b016-e6a9731a8297.png)


---
