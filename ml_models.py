"""
Retail Store Sales Analysis - Machine Learning Models
Author: Retail Analytics Team
Date: 2024
Description: Comprehensive ML models for sales forecasting, customer churn prediction, and RFM segmentation
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import warnings
warnings.filterwarnings('ignore')

# Machine Learning Libraries
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.model_selection import train_test_split, cross_val_score, TimeSeriesSplit
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import (accuracy_score, classification_report, confusion_matrix, 
                           mean_absolute_error, mean_squared_error, r2_score, roc_auc_score)
from sklearn.cluster import KMeans
import joblib

# Statistical Libraries
from scipy import stats
import statsmodels.api as sm
from statsmodels.tsa.arima.model import ARIMA
from statsmodels.tsa.seasonal import seasonal_decompose
from statsmodels.tsa.statespace.sarimax import SARIMAX

# Visualization Libraries
import matplotlib.pyplot as plt
import seaborn as sns

class RetailSalesML:
    """
    Comprehensive Machine Learning pipeline for retail sales analysis
    """
    
    def __init__(self, data_path=None, df=None):
        """
        Initialize the ML pipeline with data
        
        Args:
            data_path (str): Path to CSV file
            df (DataFrame): Pre-loaded DataFrame
        """
        if df is not None:
            self.df = df
        elif data_path:
            self.df = pd.read_csv(data_path)
        else:
            raise ValueError("Either data_path or df must be provided")
            
        self.preprocessed = False
        self.models = {}
        self.scalers = {}
        self.results = {}
        
        # Set random seed for reproducibility
        np.random.seed(42)
        
    def preprocess_data(self):
        """
        Comprehensive data preprocessing and feature engineering
        """
        print("Starting data preprocessing...")
        
        # Create copy for preprocessing
        df_processed = self.df.copy()
        
        # 1. Date features
        df_processed['order_date'] = pd.to_datetime(df_processed['order_date'])
        df_processed['order_year'] = df_processed['order_date'].dt.year
        df_processed['order_month'] = df_processed['order_date'].dt.month
        df_processed['order_quarter'] = df_processed['order_date'].dt.quarter
        df_processed['order_day_of_week'] = df_processed['order_date'].dt.dayofweek
        df_processed['order_day_of_year'] = df_processed['order_date'].dt.dayofyear
        
        # 2. Customer-level features
        customer_features = self._create_customer_features(df_processed)
        df_processed = df_processed.merge(customer_features, on='customer_id', how='left')
        
        # 3. Product-level features
        product_features = self._create_product_features(df_processed)
        df_processed = df_processed.merge(product_features, on='product_id', how='left')
        
        # 4. Time-based features
        df_processed = self._create_time_features(df_processed)
        
        # 5. Economic features
        df_processed = self._create_economic_features(df_processed)
        
        # 6. Target variable engineering
        df_processed = self._create_target_variables(df_processed)
        
        self.df_processed = df_processed
        self.preprocessed = True
        
        print(f"Preprocessing completed. Final dataset shape: {df_processed.shape}")
        return df_processed
    
    def _create_customer_features(self, df):
        """Create customer-level features for RFM analysis"""
        customer_features = df.groupby('customer_id').agg({
            'order_date': ['max', 'min', 'count'],
            'sales': ['sum', 'mean', 'std'],
            'profit': ['sum', 'mean'],
            'quantity': 'sum',
            'discount': 'mean',
            'category': 'nunique',
            'sub_category': 'nunique'
        }).round(2)
        
        # Flatten column names
        customer_features.columns = ['_'.join(col).strip() for col in customer_features.columns.values]
        
        # Rename columns
        customer_features = customer_features.rename(columns={
            'order_date_max': 'last_order_date',
            'order_date_min': 'first_order_date',
            'order_date_count': 'order_frequency',
            'sales_sum': 'total_sales',
            'sales_mean': 'avg_order_value',
            'sales_std': 'std_order_value',
            'profit_sum': 'total_profit',
            'profit_mean': 'avg_profit',
            'quantity_sum': 'total_quantity',
            'discount_mean': 'avg_discount',
            'category_nunique': 'unique_categories',
            'sub_category_nunique': 'unique_subcategories'
        })
        
        # Calculate additional features
        customer_features['customer_lifetime_days'] = (
            customer_features['last_order_date'] - customer_features['first_order_date']
        ).dt.days
        
        customer_features['days_since_last_order'] = (
            pd.to_datetime('2017-12-31') - customer_features['last_order_date']
        ).dt.days
        
        customer_features['profit_margin'] = (
            customer_features['total_profit'] / customer_features['total_sales']
        ).round(4)
        
        return customer_features.reset_index()
    
    def _create_product_features(self, df):
        """Create product-level features"""
        product_features = df.groupby('product_id').agg({
            'sales': ['sum', 'mean', 'count'],
            'profit': ['sum', 'mean'],
            'quantity': 'sum',
            'discount': 'mean',
            'customer_id': 'nunique'
        }).round(2)
        
        product_features.columns = ['_'.join(col).strip() for col in product_features.columns.values]
        
        product_features = product_features.rename(columns={
            'sales_sum': 'product_total_sales',
            'sales_mean': 'product_avg_sales',
            'sales_count': 'product_order_count',
            'profit_sum': 'product_total_profit',
            'profit_mean': 'product_avg_profit',
            'quantity_sum': 'product_total_quantity',
            'discount_mean': 'product_avg_discount',
            'customer_id_nunique': 'unique_customers'
        })
        
        product_features['product_profit_margin'] = (
            product_features['product_total_profit'] / product_features['product_total_sales']
        ).round(4)
        
        return product_features.reset_index()
    
    def _create_time_features(self, df):
        """Create time-based features"""
        # Seasonal features
        df['is_holiday_season'] = df['order_month'].isin([11, 12]).astype(int)
        df['is_year_end'] = df['order_month'].isin([12]).astype(int)
        df['is_year_start'] = df['order_month'].isin([1]).astype(int)
        
        # Rolling features will be created during time series analysis
        return df
    
    def _create_economic_features(self, df):
        """Create economic indicator features"""
        # These would typically come from external data sources
        # For demonstration, we'll create some synthetic features
        
        # Monthly economic indicators (synthetic)
        monthly_econ = df.groupby(['order_year', 'order_month']).agg({
            'sales': 'sum',
            'profit': 'sum'
        }).reset_index()
        
        monthly_econ['sales_growth'] = monthly_econ['sales'].pct_change()
        monthly_econ['market_volatility'] = monthly_econ['sales_growth'].rolling(3).std()
        
        df = df.merge(
            monthly_econ[['order_year', 'order_month', 'sales_growth', 'market_volatility']],
            on=['order_year', 'order_month'],
            how='left'
        )
        
        return df
    
    def _create_target_variables(self, df):
        """Create target variables for different ML tasks"""
        
        # 1. Churn prediction target (customers with no orders in last 6 months)
        churn_cutoff = pd.to_datetime('2017-12-31') - pd.Timedelta(days=180)
        churn_customers = df[df['order_date'] <= churn_cutoff].groupby('customer_id').agg({
            'order_date': 'max'
        })
        churn_customers['is_churned'] = (
            churn_customers['order_date'] <= churn_cutoff
        ).astype(int)
        
        df = df.merge(churn_customers[['is_churned']], on='customer_id', how='left')
        df['is_churned'] = df['is_churned'].fillna(0)
        
        # 2. High-value customer target (top 20% by profit)
        customer_profit = df.groupby('customer_id')['profit'].sum()
        high_value_threshold = customer_profit.quantile(0.8)
        high_value_customers = (customer_profit >= high_value_threshold).astype(int)
        high_value_customers.name = 'is_high_value'
        
        df = df.merge(high_value_customers, on='customer_id', how='left')
        
        return df

    def train_churn_model(self, test_size=0.2):
        """
        Train Random Forest model for customer churn prediction
        
        Args:
            test_size (float): Proportion of data for testing
            
        Returns:
            dict: Model performance metrics
        """
        if not self.preprocessed:
            self.preprocess_data()
            
        print("Training Churn Prediction Model...")
        
        # Prepare features for churn prediction
        churn_features = [
            'order_frequency', 'total_sales', 'avg_order_value', 'total_profit',
            'avg_discount', 'unique_categories', 'customer_lifetime_days',
            'days_since_last_order', 'profit_margin', 'std_order_value'
        ]
        
        # Get customer-level data
        customer_data = self.df_processed.groupby('customer_id').first().reset_index()
        
        # Handle missing values
        customer_data = customer_data.dropna(subset=churn_features + ['is_churned'])
        
        X = customer_data[churn_features]
        y = customer_data['is_churned']
        
        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42, stratify=y
        )
        
        # Scale features
        scaler = StandardScaler()
        X_train_scaled = scaler.fit_transform(X_train)
        X_test_scaled = scaler.transform(X_test)
        
        self.scalers['churn'] = scaler
        
        # Train Random Forest model
        rf_model = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=20,
            class_weight='balanced',
            random_state=42
        )
        
        rf_model.fit(X_train_scaled, y_train)
        self.models['churn'] = rf_model
        
        # Make predictions
        y_pred = rf_model.predict(X_test_scaled)
        y_pred_proba = rf_model.predict_proba(X_test_scaled)[:, 1]
        
        # Calculate metrics
        accuracy = accuracy_score(y_test, y_pred)
        auc_roc = roc_auc_score(y_test, y_pred_proba)
        
        # Feature importance
        feature_importance = pd.DataFrame({
            'feature': churn_features,
            'importance': rf_model.feature_importances_
        }).sort_values('importance', ascending=False)
        
        # Store results
        self.results['churn'] = {
            'accuracy': accuracy,
            'auc_roc': auc_roc,
            'feature_importance': feature_importance,
            'classification_report': classification_report(y_test, y_pred),
            'confusion_matrix': confusion_matrix(y_test, y_pred),
            'y_test': y_test,
            'y_pred': y_pred,
            'y_pred_proba': y_pred_proba
        }
        
        print(f"Churn Model Performance:")
        print(f"Accuracy: {accuracy:.4f}")
        print(f"AUC-ROC: {auc_roc:.4f}")
        print("\nTop 5 Features:")
        print(feature_importance.head())
        
        return self.results['churn']
    
    def train_sales_forecast_arima(self, order=(2,1,2), seasonal_order=(1,1,1,12)):
        """
        Train ARIMA model for sales forecasting
        
        Args:
            order (tuple): ARIMA order (p,d,q)
            seasonal_order (tuple): Seasonal order (P,D,Q,s)
            
        Returns:
            dict: Model performance and forecasts
        """
        print("Training ARIMA Sales Forecasting Model...")
        
        # Prepare time series data
        daily_sales = self.df_processed.groupby('order_date')['sales'].sum()
        
        # Handle missing dates
        date_range = pd.date_range(
            start=daily_sales.index.min(),
            end=daily_sales.index.max(),
            freq='D'
        )
        daily_sales = daily_sales.reindex(date_range, fill_value=0)
        
        # Split data (last 6 months for testing)
        split_date = daily_sales.index.max() - pd.Timedelta(days=180)
        train_data = daily_sales[daily_sales.index <= split_date]
        test_data = daily_sales[daily_sales.index > split_date]
        
        # Train SARIMA model
        try:
            model = SARIMAX(
                train_data,
                order=order,
                seasonal_order=seasonal_order,
                enforce_stationarity=False,
                enforce_invertibility=False
            )
            fitted_model = model.fit(disp=False)
            
            # Forecast
            forecast_steps = len(test_data)
            forecast = fitted_model.get_forecast(steps=forecast_steps)
            forecast_mean = forecast.predicted_mean
            forecast_ci = forecast.conf_int()
            
            # Calculate metrics
            mae = mean_absolute_error(test_data, forecast_mean)
            rmse = np.sqrt(mean_squared_error(test_data, forecast_mean))
            mape = np.mean(np.abs((test_data - forecast_mean) / test_data)) * 100
            
            # Store model and results
            self.models['sales_forecast'] = fitted_model
            self.results['sales_forecast'] = {
                'mae': mae,
                'rmse': rmse,
                'mape': mape,
                'train_data': train_data,
                'test_data': test_data,
                'forecast': forecast_mean,
                'confidence_interval': forecast_ci,
                'model_summary': fitted_model.summary()
            }
            
            print(f"ARIMA Model Performance:")
            print(f"MAE: ${mae:,.2f}")
            print(f"RMSE: ${rmse:,.2f}")
            print(f"MAPE: {mape:.2f}%")
            
        except Exception as e:
            print(f"ARIMA model training failed: {e}")
            # Fallback to simple moving average
            self._fallback_forecast(train_data, test_data)
            
        return self.results['sales_forecast']
    
    def _fallback_forecast(self, train_data, test_data):
        """Fallback forecasting method using moving average"""
        # Simple moving average forecast
        window = 30
        last_values = train_data.tail(window)
        forecast_mean = pd.Series([last_values.mean()] * len(test_data), index=test_data.index)
        
        mae = mean_absolute_error(test_data, forecast_mean)
        rmse = np.sqrt(mean_squared_error(test_data, forecast_mean))
        mape = np.mean(np.abs((test_data - forecast_mean) / test_data)) * 100
        
        self.results['sales_forecast'] = {
            'mae': mae,
            'rmse': rmse,
            'mape': mape,
            'train_data': train_data,
            'test_data': test_data,
            'forecast': forecast_mean,
            'confidence_interval': None,
            'model_summary': 'Simple Moving Average Fallback'
        }
        
        print("Using fallback moving average forecast")
        print(f"MAE: ${mae:,.2f}, RMSE: ${rmse:,.2f}, MAPE: {mape:.2f}%")
    
    def perform_rfm_segmentation(self, n_clusters=5):
        """
        Perform RFM segmentation using K-means clustering
        
        Args:
            n_clusters (int): Number of clusters for segmentation
            
        Returns:
            dict: Segmentation results and cluster profiles
        """
        if not self.preprocessed:
            self.preprocess_data()
            
        print("Performing RFM Segmentation...")
        
        # Prepare RFM data
        rfm_data = self.df_processed.groupby('customer_id').agg({
            'days_since_last_order': 'first',
            'order_frequency': 'first',
            'total_sales': 'first'
        }).dropna()
        
        # Rename for RFM
        rfm_data = rfm_data.rename(columns={
            'days_since_last_order': 'recency',
            'order_frequency': 'frequency',
            'total_sales': 'monetary'
        })
        
        # Handle outliers
        for column in ['recency', 'frequency', 'monetary']:
            Q1 = rfm_data[column].quantile(0.25)
            Q3 = rfm_data[column].quantile(0.75)
            IQR = Q3 - Q1
            lower_bound = Q1 - 1.5 * IQR
            upper_bound = Q3 + 1.5 * IQR
            rfm_data = rfm_data[
                (rfm_data[column] >= lower_bound) & 
                (rfm_data[column] <= upper_bound)
            ]
        
        # Scale the data
        scaler = StandardScaler()
        rfm_scaled = scaler.fit_transform(rfm_data)
        self.scalers['rfm'] = scaler
        
        # Determine optimal number of clusters using elbow method
        wcss = []
       
