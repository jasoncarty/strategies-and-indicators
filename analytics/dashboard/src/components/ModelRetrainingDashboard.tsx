import React from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  getModelHealthOverview,
  getModelAlerts,
  getModelRetrainingStatus
} from '../services/api';
import {
  CheckCircleIcon,
  ExclamationTriangleIcon,
  XCircleIcon,
  InformationCircleIcon,
  ArrowPathIcon
} from '@heroicons/react/24/outline';

interface RetrainingStatus {
  model_key: string;
  last_trained?: string;
  needs_retraining: boolean;
  reason?: string;
  priority: 'low' | 'medium' | 'high' | 'critical';
  health_score: number;
  status: 'healthy' | 'warning' | 'critical' | 'no_data';
}

const ModelRetrainingDashboard: React.FC = () => {
  const navigate = useNavigate();
  // Fetch model health and alerts data
  const { data: healthData, isLoading: healthLoading } = useQuery({
    queryKey: ['modelHealth'],
    queryFn: getModelHealthOverview,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  const { data: alertsData, isLoading: alertsLoading } = useQuery({
    queryKey: ['modelAlerts'],
    queryFn: getModelAlerts,
    refetchInterval: 30000,
  });

  const { data: retrainingData, isLoading: retrainingLoading } = useQuery({
    queryKey: ['modelRetrainingStatus'],
    queryFn: getModelRetrainingStatus,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  // Process data to create retraining recommendations
  const getRetrainingRecommendations = (): RetrainingStatus[] => {
    if (!healthData?.models || !alertsData?.alerts || !retrainingData?.models) return [];

    const recommendations: RetrainingStatus[] = [];
    const alertsByModel = new Map();

    // Group alerts by model
    alertsData.alerts.forEach((alert: any) => {
      if (!alertsByModel.has(alert.model_key)) {
        alertsByModel.set(alert.model_key, []);
      }
      alertsByModel.set(alert.model_key, [...alertsByModel.get(alert.model_key), ...alert.alerts]);
    });

    // Create a map of retraining data by model key
    const retrainingByModel = new Map();
    retrainingData.models.forEach((retrainModel: any) => {
      retrainingByModel.set(retrainModel.model_key, retrainModel);
    });

    // Process each model
    healthData.models.forEach((model: any) => {
      const modelAlerts = alertsByModel.get(model.model_key) || [];
      const retrainInfo = retrainingByModel.get(model.model_key);
      const needsRetraining = modelAlerts.some((alert: any) => alert.level === 'critical' || alert.level === 'warning');

      let reason = '';
      let priority: 'low' | 'medium' | 'high' | 'critical' = 'low';

      // Determine retraining reason and priority
      if (modelAlerts.some((alert: any) => alert.type === 'confidence_inversion')) {
        reason = 'Confidence system broken';
        priority = 'critical';
      } else if (model.health_score < 60) {
        reason = `Low health score: ${model.health_score}/100`;
        priority = 'high';
      } else if (model.health_score < 80) {
        reason = `Moderate health score: ${model.health_score}/100`;
        priority = 'medium';
      } else if (modelAlerts.length > 0) {
        reason = `${modelAlerts.length} alerts detected`;
        priority = 'medium';
      }

      recommendations.push({
        model_key: model.model_key,
        last_trained: retrainInfo?.last_retrained || retrainInfo?.training_date,
        needs_retraining: needsRetraining || model.health_score < 70,
        reason,
        priority,
        health_score: model.health_score,
        status: model.status
      });
    });

    return recommendations.sort((a, b) => {
      const priorityOrder = { critical: 0, high: 1, medium: 2, low: 3 };
      return priorityOrder[a.priority] - priorityOrder[b.priority];
    });
  };

  const recommendations = getRetrainingRecommendations();
  // Create a map of retraining data by model key for table access
  const retrainingByModel = new Map();
  if (retrainingData?.models) {
    retrainingData.models.forEach((retrainModel: any) => {
      retrainingByModel.set(retrainModel.model_key, retrainModel);
    });
  }

  const criticalModels = recommendations.filter(r => r.priority === 'critical');
  const highPriorityModels = recommendations.filter(r => r.priority === 'high');
  const needsRetraining = recommendations.filter(r => r.needs_retraining);

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'critical': return 'text-red-600 bg-red-50 border-red-200';
      case 'high': return 'text-orange-600 bg-orange-50 border-orange-200';
      case 'medium': return 'text-yellow-600 bg-yellow-50 border-yellow-200';
      case 'low': return 'text-green-600 bg-green-50 border-green-200';
      default: return 'text-gray-600 bg-gray-50 border-gray-200';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy': return <CheckCircleIcon className="h-5 w-5 text-green-500" />;
      case 'warning': return <ExclamationTriangleIcon className="h-5 w-5 text-yellow-500" />;
      case 'critical': return <XCircleIcon className="h-5 w-5 text-red-500" />;
      default: return <InformationCircleIcon className="h-5 w-5 text-gray-500" />;
    }
  };

  const formatDate = (timestamp: string | number) => {
    if (!timestamp) return 'Never';

    // Handle ISO date strings (from retraining metadata)
    if (typeof timestamp === 'string' && timestamp.includes('T')) {
      const date = new Date(timestamp);
      return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    }

    // Handle Unix timestamps (from health data)
    const date = new Date(Number(timestamp) * 1000);
    return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
  };

  const handleManualRetrain = async (modelKey: string) => {
    // TODO: Implement manual retraining API call
    console.log(`Manual retraining requested for ${modelKey}`);
    alert(`Manual retraining requested for ${modelKey}. This feature will be implemented in the next update.`);
  };

  if (healthLoading || alertsLoading || retrainingLoading) {
    return (
      <div className="min-h-screen bg-gray-50 p-6">
        <div className="max-w-7xl mx-auto">
          <div className="animate-pulse">
            <div className="h-8 bg-gray-200 rounded w-1/4 mb-6"></div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
              {[1, 2, 3].map(i => (
                <div key={i} className="h-32 bg-gray-200 rounded"></div>
              ))}
            </div>
            <div className="h-96 bg-gray-200 rounded"></div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="mb-8">
          <button
              onClick={() => navigate('/')}
              className="text-blue-600 hover:text-blue-800 mb-2 flex items-center"
            >
            ← Back to Dashboard
          </button>
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            Model Retraining Dashboard
          </h1>
          <p className="text-gray-600">
            Monitor model health and manage automated retraining
          </p>
        </div>

        {/* Summary Cards */}
        <div className="grid grid-cols-1 md:grid-cols-5 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow p-6 border-l-4 border-red-500">
            <div className="flex items-center">
              <XCircleIcon className="h-8 w-8 text-red-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Critical Models</p>
                <p className="text-2xl font-bold text-red-600">{criticalModels.length}</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6 border-l-4 border-orange-500">
            <div className="flex items-center">
              <ExclamationTriangleIcon className="h-8 w-8 text-orange-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">High Priority</p>
                <p className="text-2xl font-bold text-orange-600">{highPriorityModels.length}</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6 border-l-4 border-yellow-500">
            <div className="flex items-center">
              <ArrowPathIcon className="h-8 w-8 text-yellow-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Need Retraining</p>
                <p className="text-2xl font-bold text-yellow-600">{needsRetraining.length}</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6 border-l-4 border-green-500">
            <div className="flex items-center">
              <CheckCircleIcon className="h-8 w-8 text-green-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Healthy Models</p>
                <p className="text-2xl font-bold text-green-600">
                  {recommendations.filter(r => r.status === 'healthy').length}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6 border-l-4 border-blue-500">
            <div className="flex items-center">
              <ArrowPathIcon className="h-8 w-8 text-blue-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Retrained Models</p>
                <p className="text-2xl font-bold text-blue-600">
                  {retrainingData?.summary?.retrained_models || 0}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Retraining Status Table */}
        <div className="bg-white rounded-lg shadow">
          <div className="px-4 py-2 border-b border-gray-200">
            <h2 className="text-lg font-medium text-gray-900">Model Retraining Status</h2>
            <p className="text-sm text-gray-600 mt-1">
              {recommendations.length} models monitored • Last updated: {new Date().toLocaleTimeString()}
            </p>
          </div>

          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200 border-spacing-0">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Model
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Health Score
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Last Trained
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Model Version
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Retraining Needed
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {recommendations.map((model) => {
                  const retrainInfo = retrainingByModel.get(model.model_key);
                  return (
                  <tr key={model.model_key} className="hover:bg-gray-50">
                    <td className="px-4 py-2 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className="flex-shrink-0 h-8 w-8">
                          {getStatusIcon(model.status)}
                        </div>
                        <div className="ml-4">
                          <div className="text-sm font-small text-gray-900">
                            {model.model_key}
                          </div>
                          <div className="text-sm font-small text-gray-500">
                            {model.model_key.split('_')[1]} {model.model_key.split('_')[3]}
                          </div>
                        </div>
                      </div>
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap">
                      <span className={`inline-flex text-sm font-small items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getPriorityColor(model.priority)}`}>
                        {model.priority.charAt(0).toUpperCase() + model.priority.slice(1)}
                      </span>
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className="w-16 bg-gray-200 rounded-full h-2 mr-2">
                          <div
                            className={`h-2 rounded-full ${
                              model.health_score >= 80 ? 'bg-green-500' :
                              model.health_score >= 60 ? 'bg-yellow-500' : 'bg-red-500'
                            }`}
                            style={{ width: `${model.health_score}%` }}
                          ></div>
                        </div>
                        <span className="text-sm font-small text-gray-900">{model.health_score}/100</span>
                      </div>
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap text-sm font-small  text-gray-500">
                      {model.last_trained ? formatDate(model.last_trained) : 'Never'}
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap text-sm font-small  text-gray-500">
                      <div className="flex items-center">
                        <span className="text-sm font-small  text-gray-900">
                          v{retrainInfo?.model_version || 1.0}
                        </span>
                        {retrainInfo?.retrained_by && (
                          <span className="ml-2 inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            {retrainInfo.retrained_by}
                          </span>
                        )}
                      </div>
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap">
                      {model.needs_retraining ? (
                        <div className="flex items-center">
                          <ExclamationTriangleIcon className="h-4 w-4 text-red-500 mr-1" />
                          <span className="text-sm text-red-600 font-medium">Yes</span>
                          {model.reason && (
                            <span className="text-xs text-gray-500 ml-2">({model.reason})</span>
                          )}
                        </div>
                      ) : (
                        <div className="flex items-center">
                          <CheckCircleIcon className="h-4 w-4 text-green-500 mr-1" />
                          <span className="text-sm text-green-600 font-medium">No</span>
                        </div>
                      )}
                    </td>

                    <td className="px-4 py-2 whitespace-nowrap text-sm font-medium">
                      <button
                        onClick={() => handleManualRetrain(model.model_key)}
                        disabled={!model.needs_retraining}
                        className={`inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded-md ${
                          model.needs_retraining
                            ? 'text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500'
                            : 'text-gray-400 bg-gray-100 cursor-not-allowed'
                        }`}
                      >
                        <ArrowPathIcon className="h-3 w-3 mr-1" />
                        Retrain
                      </button>
                    </td>
                  </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        {/* Configuration Section */}
        <div className="mt-8 bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-medium text-gray-900 mb-4">Retraining Configuration</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <h4 className="text-sm font-medium text-gray-700 mb-2">Automated Retraining</h4>
              <div className="space-y-2">
                <div className="flex items-center">
                  <input type="checkbox" id="auto-critical" className="mr-2" defaultChecked />
                  <label htmlFor="auto-critical" className="text-sm text-gray-600">
                    Auto-retrain critical models
                  </label>
                </div>
                <div className="flex items-center">
                  <input type="checkbox" id="auto-warnings" className="mr-2" />
                  <label htmlFor="auto-warnings" className="text-sm text-gray-600">
                    Auto-retrain warning models
                  </label>
                </div>
              </div>
            </div>

            <div>
              <h4 className="text-sm font-medium text-gray-700 mb-2">Monitoring Settings</h4>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600">Check interval:</span>
                  <span className="text-sm font-medium text-gray-900">60 minutes</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600">Max concurrent:</span>
                  <span className="text-sm font-medium text-gray-900">2 models</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ModelRetrainingDashboard;
