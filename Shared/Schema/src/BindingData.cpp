#include "hmi/schema/BindingData.h"

namespace hmi::schema {

QJsonObject BindingData::toJson() const
{
    QJsonObject obj;
    obj["property"] = property;
    obj["variable"] = variable;
    return obj;
}

BindingData BindingData::fromJson(const QJsonObject &obj)
{
    BindingData b;
    b.property = obj.value("property").toString();
    b.variable = obj.value("variable").toString();
    return b;
}

bool BindingData::isValidJson(const QJsonObject &obj)
{
    return obj.value("property").isString() && !obj.value("property").toString().isEmpty()
        && obj.value("variable").isString() && !obj.value("variable").toString().isEmpty();
}

} // namespace hmi::schema
