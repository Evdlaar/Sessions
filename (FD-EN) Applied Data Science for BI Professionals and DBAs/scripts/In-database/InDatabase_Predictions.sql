/*
Applied Data Science for BI Professionals and DBAs
(c) Enrico van de Laar
*/

USE [DSTraining]
GO

-- Look at the data
SELECT * FROM iris

-- We want to predict the species based on the four features
-- The first step is to build a model, we can do this directly from inside SQL Server using R code
-- through the new sp_execute_external_script!

-- First we have to enable the external scripts option
EXEC sp_configure 'external scripts enabled',1
RECONFIGURE WITH OVERRIDE
GO

-- Let's train the model
-- For this I am going to split the IRIS table into a training and testing set
-- Select 10% of the rows into a new test table
SELECT TOP 10 PERCENT * 
INTO IRIS_Test
FROM IRIS ORDER BY NEWID()

-- Place the remaining 90% into a train table
SELECT * 
INTO IRIS_Train
FROM IRIS
EXCEPT
SELECT * FROM IRIS_Test

select * from IRIS_Train
select * from IRIS_Test

-- We are going to train a model through the sp_execute_external_script procedure
-- Afterwards we can "serialize" the model and store it inside a table (models)
-- This makes it easy to call the model when we want to score new data.

-- Declare the variable that will hold the model
DECLARE @model VARBINARY(MAX)

EXEC sp_execute_external_script  
	@language = N'R', -- R script (Python is supported in SQL Server 2017)
	@script = N'  
               iris.DTree <- rxBTrees(formula = Species ~ Sepal_Length + Sepal_Width + Petal_Length + Petal_Width, data = iris, 
										maxDepth = 3, nTree = 50, seed = 0, lossFunction = "multinomial")             
               model <- rxSerializeModel(iris.DTree, realtimeScoringOnly = FALSE)', -- Actual R code to create the model, notice the use of rx (RevoScaleR) functions
	@input_data_1 = N'SELECT *  FROM IRIS_Train', -- Input data for the model
	@input_data_1_name = N'iris', -- The name of the input data data frame that we can reference in the R code
	@params = N'@model varbinary(max) OUTPUT', -- Set the variable name to the one used in the R code
	@model = @model OUTPUT -- Output the model variable

-- Insert the model into the models table
INSERT INTO models (model_name, model_version, model_object)
VALUES ('iris.Dtree','v1', @model)

-- Let's check the models table
SELECT * FROM models

-- Now that we stored our model inside a table
-- let's use it again the test data we seperated earlier

-- We are going to set another variable that will contain the model from the table
DECLARE @iris_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'iris.Dtree')

-- Let's run another bit of R code to test the model performance again the test table we created earlier
EXECUTE sp_execute_external_script
	@language = N'R',
	@script = N'
				model = rxUnserializeModel(iris_model);
				iris_prediction = rxPredict(model, iris_test)
				iris_pred_results <- cbind(iris_test, iris_prediction)',
	@input_data_1 = N'SELECT Sepal_Length, Sepal_Width, Petal_Length, Petal_Width, Species FROM IRIS_Test',
	@input_data_1_name = N'iris_test',
	@output_data_1_name = N'iris_pred_results',
	@params = N'@iris_model varbinary(max)',
	@iris_model = @iris_model_raw
 WITH RESULT SETS (("Sepal_Length" FLOAT, "Sepal_Width" FLOAT, "Petal_Length" FLOAT, "Petal_Width" FLOAT, "Species" VARCHAR(100),
					"setosa_prob" FLOAT, "versicolor_prob" FLOAT, "virginica_prob" FLOAT, "Species_Pred" VARCHAR(100)))

-- If you run SQL Server 2017 a new function called PREDICT is available which makes the code far easier,
-- doesn't require you to manually de-serialize the model and performs better
DECLARE @iris_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'iris.Dtree')

SELECT 
  a.*, 
  p.*
 FROM PREDICT(MODEL = @iris_model_raw, DATA = dbo.IRIS_test as a)
 WITH("setosa_prob" FLOAT, "versicolor_prob" FLOAT, "virginica_prob" FLOAT, "Species_Pred" VARCHAR(100)) as p;

-- So this is pretty cool but how can we operationalize this model?
-- For instance, it would be awesome if we can get a real-time prediction on data when it comes in!
-- We can do this by using a trigger for instance

-- First, let's convert the prediction code to a Stored Procedure
CREATE PROCEDURE [dbo].[sp_Predict_Iris]
   @sepal_length REAL,
   @sepal_width REAL,
   @petal_length REAL,
   @petal_width REAL,
   @predicted_species VARCHAR(50) OUTPUT
 AS
   
   DECLARE @iris_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'iris.Dtree')

   EXEC sp_execute_external_script
     @language= N'R',
     @script = N'
			    model = rxUnserializeModel(iris_model);

				df.sl <- sepal_length_R
				df.sw <- sepal_width_R
				df.pl <- petal_length_R
				df.pw <- petal_width_R

				df <- data.frame(df.sl, df.sw, df.pl, df.pw)
				colnames(df) <- c("Sepal_Length", "Sepal_Width", "Petal_Length", "Petal_Width")

				prediction <- rxPredict(modelObject = model, data = df)
				predicted_species_R <- prediction$Species_Pred',
	 @params = N'@iris_model varbinary(max),
				 @sepal_length_R real,
				 @sepal_width_R real,
				 @petal_length_R real,
			     @petal_width_R real,
			     @predicted_species_R varchar(50) OUTPUT',
	 @iris_model = @iris_model_raw,
     @sepal_length_R = @sepal_length,
     @sepal_width_R = @sepal_width,
     @petal_length_R = @petal_length,
     @petal_width_R = @petal_width,
     @predicted_species_R = @predicted_species OUTPUT
     WITH RESULT SETS NONE;

RETURN
GO

-- Let's see if the SP works
DECLARE @prediction_results VARCHAR(50)

EXEC sp_Predict_Iris 
		@sepal_length = 6.69, 
		@sepal_width = 3, 
		@petal_length = 5, 
		@petal_width = 1.7, 
		@predicted_species = @prediction_results OUTPUT

SELECT @prediction_results

-- Now that we have the SP in place we can build a trigger that will kick off the SP when a new row is inserted
CREATE TRIGGER trgPredictSpecies ON dbo.IRIS_TRIGGER
 INSTEAD OF Insert
   AS
     DECLARE @sepal_length_TR REAL
     DECLARE @sepal_width_TR REAL
     DECLARE @petal_length_TR REAL
     DECLARE @petal_width_TR REAL
 
     SELECT @sepal_length_TR = i.Sepal_Length FROM inserted i
     SELECT @sepal_width_TR = i.Sepal_Width FROM inserted i
     SELECT @petal_length_TR = i.Petal_Length FROM inserted i
     SELECT @petal_width_TR = i.Petal_Width FROM inserted i

    DECLARE @predicted_output VARCHAR(50)

    -- Execute the Stored Procedure
     EXEC sp_Predict_Iris 
       @sepal_length = @sepal_length_TR, 
       @sepal_width = @sepal_width_TR,
       @petal_length = @petal_length_TR,
       @petal_width = @petal_width_TR,
       @predicted_species = @predicted_output OUTPUT

    -- Insert the values we supplied on the INSERT statement together with the
    -- predicted species class we retrieved from the AzureML web service
    INSERT INTO IRIS_TRIGGER (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width, Species)
    VALUES (@sepal_length_TR, @sepal_width_TR, @petal_length_TR, @petal_width_TR, @predicted_output)

-- Check the IRIS_TRIGGER table content
SELECT * FROM IRIS_TRIGGER

-- Now insert some data into the IRIS_TRIGGER table (should predict to versicolor)
INSERT INTO IRIS_TRIGGER (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width)
VALUES (6.1, 2.9, 4.7, 1.4)

-- Lets check the table again
SELECT * FROM IRIS_TRIGGER

-- Let's add another row (should be setosa)
INSERT INTO IRIS_TRIGGER (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width)
VALUES (5.1, 3.5, 1.4, 0.2)

-- Lets check the table again
SELECT * FROM IRIS_TRIGGER




-- Cleanup
DROP TABLE IRIS_Test
DROP TABLE IRIS_Train
TRUNCATE TABLE models
TRUNCATE TABLE IRIS_TRIGGER
DROP PROCEDURE sp_Predict_Iris
DROP TRIGGER trgPredictSpecies